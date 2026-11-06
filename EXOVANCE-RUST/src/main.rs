mod backend;
mod host;
mod journal;
mod model;
mod power;
mod ui;
use crate::{
    journal::Journal,
    model::{Entry, Reply},
};
use anyhow::{bail, Context, Result};
use clap::Parser;
use serde_json::json;
use std::{
    path::{Path, PathBuf},
    sync::mpsc::TryRecvError,
};

#[derive(Parser)]
#[command(
    name = "Exovance",
    version,
    about = "Exovance: консольное меню Windows и управление схемами питания"
)]
struct Args {
    #[arg(long, help = "Просмотр интерфейса без применения настроек")]
    demo: bool,
    #[arg(
        long,
        help = "Текстовый кадр интерфейса; не создаёт журнал и не запускает PowerShell"
    )]
    snapshot: bool,
    #[arg(
        long,
        help = "Проверка Windows, ресурсов и синтаксиса без применения настроек"
    )]
    check: bool,
    #[arg(long, help = "Список всех разделов в JSON, без изменения настроек")]
    list: bool,
    #[arg(
        long,
        help = "Каталог комплекта с Resources, DEVICE-TWEAKER-V2 и POWER-PLAN"
    )]
    root: Option<PathBuf>,
    #[arg(long, default_value_t = 116)]
    width: u16,
    #[arg(long, default_value_t = 36)]
    height: u16,
}
fn status(log: &Journal) -> String {
    format!(
        "Ошибок: {} · замечаний: {} · F1: описание перед применением",
        log.errors, log.warnings
    )
}
fn run_section(ui: &mut ui::Ui, root: &Path, route: &str, log: &mut Journal) -> Result<()> {
    log.event(
        "info",
        "section_started",
        "Открыт раздел Windows",
        json!({"route":route,"engine":"Windows PowerShell 5.1"}),
    )?;
    let mut worker = backend::Backend::start(root, &log.directory, route)?;
    let mut disconnected = false;
    loop {
        for _ in 0..64 {
            match worker.events.try_recv() {
                Ok(backend::Event::Output(line)) => log.output(&line)?,
                Ok(backend::Event::PipeError(message)) => {
                    bail!("Ошибка связи с движком: {message}");
                }
                Ok(backend::Event::Request(request)) => {
                    let mut reply = Reply {
                        id: request.id,
                        ..Default::default()
                    };
                    match request.kind.as_str() {
                        "status" => {
                            let level = match request.level.as_str() {
                                "error" => "error",
                                "warning" => "warning",
                                _ => "info",
                            };
                            log.event(
                                level,
                                "windows_status",
                                &request.title,
                                json!({"route":route}),
                            )?;
                            continue;
                        }
                        "menu" => {
                            let selection = ui.choose_at(
                                &request.title,
                                &request.entries,
                                &status(log),
                                request.selected,
                            )?;
                            reply.cancelled = selection.is_none();
                            reply.index = selection.unwrap_or(0);
                            log.event(
                                "info",
                                "menu_choice",
                                "Выбор пункта",
                                json!({"title":request.title,"index":selection}),
                            )?;
                        }
                        "input" => {
                            let input=ui.input(&request.title,&format!("{}\n\nВвод передаётся действующему разделу Windows. Esc возвращает пустой ответ и отменяет подтверждение.",log.tail.iter().rev().take(14).cloned().collect::<Vec<_>>().into_iter().rev().collect::<Vec<_>>().join("\n")))?;
                            reply.cancelled = input.is_none();
                            reply.text = input.unwrap_or_default();
                            // Prompt answers are not copied to logs (paths or other private data may be entered).
                            log.event(
                                "info",
                                "prompt_answered",
                                "Запрос ввода обработан",
                                json!({"cancelled":reply.cancelled}),
                            )?;
                        }
                        "pause" => {
                            ui.text(&request.title, &log.tail.join("\n"), &status(log))?;
                        }
                        _ => bail!("Неизвестный запрос движка"),
                    }
                    worker.reply(&reply)?;
                }
                Err(TryRecvError::Empty) => break,
                Err(TryRecvError::Disconnected) => {
                    disconnected = true;
                    break;
                }
            }
        }
        if disconnected {
            if let Some(exit) = worker.child.try_wait()? {
                if !exit.success() {
                    bail!(
                        "Раздел Windows завершился с кодом {:?}; проверь вывод и powershell.txt",
                        exit.code()
                    );
                }
                log.event(
                    "info",
                    "section_closed",
                    "Раздел закрыт. Код 0 не подтверждает успешность каждого изменения.",
                    json!({"route":route,"exit_code":exit.code()}),
                )?;
                return Ok(());
            }
        }
        ui.busy("Выполнение раздела Windows", &log.tail, &status(log))?;
    }
}
fn native_power(ui: &mut ui::Ui, root: &Path, log: &mut Journal) -> Result<()> {
    loop {
        let mut entries = vec![
            Entry::action(0, "Список схем и активная схема", "list"),
            Entry::action(1, "Импортировать и активировать Exovance v2", "apply"),
            Entry::action(2, "Экспортировать активную схему", "export"),
            Entry::action(3, "Открыть Электропитание Windows", "control"),
            Entry::action(4, "Back", "back"),
        ];
        entries[1].help=model::Help{summary:"Схема Exovance из комплекта проекта.".into(),effect:"Создать резервную копию активной схемы; импортировать Exovance, если её ещё нет, обновить подпись и активировать.".into(),r#where:format!("POWER-PLAN/EXOVANCE.pow · GUID {}",power::EXOVANCE_GUID),recommendation:"Текущая схема экспортируется до изменения. Для подтверждения введи ПРИМЕНИТЬ.".into(),..Default::default()};
        let Some(choice) = ui.choose("Схемы питания · Rust", &entries, &status(log))?
        else {
            return Ok(());
        };
        let result = (|| -> Result<()> {
            match choice {
                0 => {
                    let rows = power::list(&mut power::WindowsPower)?;
                    let active = power::active(&mut power::WindowsPower)?;
                    log.event("info", "power_schemes_read", "Прочитан список схем", json!({"active":active.to_string(),"marked_active":rows.iter().filter(|row|row.active).map(|row|row.id.to_string()).collect::<Vec<_>>() }))?;
                    let text = rows
                        .iter()
                        .map(|row| {
                            format!(
                                "{} {}\n   {}",
                                if row.id == active { "●" } else { "○" },
                                row.name,
                                row.id
                            )
                        })
                        .collect::<Vec<_>>()
                        .join("\n\n");
                    ui.text(
                        "Схемы питания",
                        &text,
                        "Только чтение · активная схема отмечена ●",
                    )?;
                }
                1 => {
                    let source = power::source(root)?;
                    let prompt=format!("Источник: {}\n\nБудет активирована Exovance v2. Прежняя активная схема сохранится в папке журнала как power-before-<ID>.pow.\n\nВведи ПРИМЕНИТЬ для продолжения.",source.display());
                    if ui.input("Подтвердить схему питания", &prompt)?.as_deref()
                        != Some("ПРИМЕНИТЬ")
                    {
                        log.event(
                            "info",
                            "power_cancelled",
                            "Активация схемы отменена",
                            json!({}),
                        )?;
                        return Ok(());
                    }
                    power::activate_exovance(&mut power::WindowsPower, &source, log)?;
                    ui.text("Схема применена",&format!("Windows подтвердила активную Exovance v2.\nРезервная копия находится в папке журнала: {}",log.directory.display()),&status(log))?;
                }
                2 => {
                    if let Some(path) = ui.input(
                        "Экспорт схемы",
                        "Полный путь нового .pow файла. Существующий файл не перезаписывается.",
                    )? {
                        if path.trim().is_empty() {
                            return Ok(());
                        }
                        let path = PathBuf::from(path);
                        if path.exists() {
                            bail!("Файл уже существует; выбери другое имя.");
                        }
                        if !path.is_absolute()
                            || path
                                .extension()
                                .and_then(|s| s.to_str())
                                .is_none_or(|e| !e.eq_ignore_ascii_case("pow"))
                        {
                            bail!("Нужен абсолютный путь с расширением .pow");
                        }
                        let id = power::active(&mut power::WindowsPower)?;
                        host::run(
                            "powercfg.exe",
                            &[
                                "/export".into(),
                                path.to_string_lossy().into_owned(),
                                id.to_string(),
                            ],
                        )?;
                        if !path.is_file() || path.metadata()?.len() == 0 {
                            bail!("Файл экспорта не создан");
                        }
                        log.event(
                            "info",
                            "power_exported",
                            "Схема экспортирована",
                            json!({"guid":id.to_string(),"path":path.display().to_string()}),
                        )?;
                    }
                }
                3 => {
                    std::process::Command::new(host::system_program("control.exe")?)
                        .args(["/name", "Microsoft.PowerOptions"])
                        .spawn()?;
                }
                _ => return Ok(()),
            }
            Ok(())
        })();
        if choice == 4 {
            return Ok(());
        }
        if let Err(error) = result {
            log.event("error", "power_failed", &format!("{error:#}"), json!({}))?;
            ui.text("Ошибка схемы питания", &format!("{error:#}"), &status(log))?;
        }
    }
}
fn overview(root: &Path) -> String {
    let mut text=format!("EXOVANCE RUST {} — предварительная версия\n\nКаталог комплекта: {}\nWindows x64: {}\nПрава администратора: {}\n\nИнтерфейс, навигация, журнал и управление схемами питания: Rust.\nОстальные операции Windows: существующий PowerShell 5.1, встроенный в EXE.\nDevice Tweaker, NVPI и другие приложения запускаются из комплекта.\n\nЭто ещё не полный перенос всех алгоритмов на Rust.\nИзменения начинаются только при выборе соответствующих действий.\n",env!("CARGO_PKG_VERSION"),root.display(),cfg!(all(windows,target_pointer_width="64")),host::is_admin());
    for path in [
        "DEVICE-TWEAKER-V2/RUN-EXOVANCE-V2.bat",
        "POWER-PLAN/EXOVANCE.pow",
        "Resources/NVIDIA-PROFILE-INSPECTOR/NVPI-R.exe",
        "Resources/POWER-SCHEME-MANAGER/POWER-SCHEME-MANAGER.exe",
    ] {
        text.push_str(&format!(
            "\n{}: {}",
            if root.join(path).is_file() {
                "Найден"
            } else {
                "Отсутствует"
            },
            path
        ));
    }
    text
}
fn main() -> std::process::ExitCode {
    let args = Args::parse();
    match run(args) {
        Ok(code) => std::process::ExitCode::from(code),
        Err(error) => {
            eprintln!("Exovance: {error:#}");
            std::process::ExitCode::FAILURE
        }
    }
}
fn run(mut args: Args) -> Result<u8> {
    if [args.demo, args.snapshot, args.check, args.list]
        .into_iter()
        .filter(|x| *x)
        .count()
        > 1
    {
        bail!("Используй один режим: --demo, --snapshot, --check или --list.");
    }
    if args.snapshot {
        print!("{}", ui::snapshot(args.width, args.height)?);
        return Ok(0);
    }
    if args.list {
        println!("{}", serde_json::to_string_pretty(&model::catalog())?);
        return Ok(0);
    }
    let root = host::resolve_root(args.root.as_deref())?;
    if args.check {
        println!("{}", overview(&root));
        if !cfg!(all(windows, target_pointer_width = "64")) {
            println!("Неподходящая ОС; изменения не выполнялись.");
            return Ok(2);
        }
        return Ok(backend::check(&root)?.try_into().unwrap_or(1));
    }
    if !args.demo {
        host::require_windows()?;
        if !host::is_admin() {
            // A normal double-click opens a usable read-only preview instead of closing a console.
            args.demo = true;
        }
    }
    let mut ui = ui::Ui::new()?;
    let mut entries = model::catalog();
    entries.insert(
        entries.len() - 1,
        Entry::action(1000, "Открыть журнал текущего запуска", "__logs"),
    );
    let mut log = if args.demo {
        None
    } else {
        Some(Journal::create(&root)?)
    };
    loop {
        let status = log
            .as_ref()
            .map(status)
            .unwrap_or("ПРОСМОТР · для изменений запусти от имени администратора".into());
        let Some(index) = ui.choose("Exovance Optimizer", &entries, &status)? else {
            break;
        };
        let entry = entries
            .iter()
            .find(|e| e.index == index && e.selectable)
            .context("Неверный пункт меню")?;
        let route = entry.value.as_str().context("Неверный маршрут меню")?;
        if route == "exit" {
            break;
        }
        if route == "preflight" {
            ui.text("О программе", &overview(&root), &status)?;
            continue;
        }
        if args.demo {
            let text = if route == "__logs" {
                "В деморежиме журнал на диск не записывается.".into()
            } else {
                format!("{}\n\nДЕМОРЕЖИМ: выбор этого раздела не запускает PowerShell, утилиты и изменение настроек.\n\n{}",entry.text,entry.help.lines())
            };
            ui.text("Просмотр раздела", &text, &status)?;
            continue;
        }
        let log = log.as_mut().unwrap();
        let result = match route {
            "__logs" => {
                log.event("info", "report_opened", "Открыт журнал", json!({}))?;
                std::process::Command::new(host::system_program("notepad.exe")?)
                    .arg(&log.report)
                    .spawn()
                    .map(|_| ())
                    .map_err(Into::into)
            }
            "powerPlan" => native_power(&mut ui, &root, log),
            _ => run_section(&mut ui, &root, route, log),
        };
        if let Err(error) = result {
            log.event(
                "error",
                "section_failed",
                &format!("{error:#}"),
                json!({"route":route,"partial_changes_possible":true}),
            )?;
            ui.text(
                "Ошибка · проверь журнал",
                &format!("{error:#}\n\nЖурнал: {}", log.report.display()),
                &status_for(log),
            )?;
        }
    }
    if let Some(log) = log.as_mut() {
        log.event("info", "session_closed", "Меню закрыто", json!({}))?;
    }
    Ok(0)
}
fn status_for(log: &Journal) -> String {
    status(log)
}
