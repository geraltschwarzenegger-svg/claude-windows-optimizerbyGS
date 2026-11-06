use crate::model::{self, Entry, Selection};
use anyhow::{bail, Result};
use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::{CrosstermBackend, TestBackend},
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, List, ListItem, ListState, Paragraph, Wrap},
    Frame, Terminal,
};
use std::io::{self, IsTerminal, Stdout};
use unicode_width::UnicodeWidthStr;
const BG: Color = Color::Rgb(12, 18, 29);
const PANEL: Color = Color::Rgb(18, 28, 42);
const MINT: Color = Color::Rgb(73, 226, 190);
const TEXT: Color = Color::Rgb(226, 236, 247);
const MUTED: Color = Color::Rgb(157, 176, 197);
fn block(title: &str) -> Block<'_> {
    Block::default()
        .title(title)
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .border_style(Style::default().fg(Color::Rgb(49, 70, 90)))
        .style(Style::default().bg(PANEL).fg(TEXT))
}
#[derive(Clone, Copy)]
enum BodyMode {
    Text,
    Input,
    Busy,
}

fn screen_areas(area: Rect) -> std::rc::Rc<[Rect]> {
    Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),
            Constraint::Min(3),
            Constraint::Length(4),
        ])
        .margin(1)
        .split(area)
}

fn frame(
    f: &mut Frame,
    title: &str,
    entries: &[Entry],
    selection: Option<usize>,
    status: &str,
    body: Option<(&str, BodyMode)>,
    scroll: u16,
) {
    f.render_widget(
        Block::default().style(Style::default().bg(BG).fg(TEXT)),
        f.area(),
    );
    let rows = screen_areas(f.area());
    f.render_widget(
        Paragraph::new(vec![
            Line::from(vec![
                Span::styled(
                    " EXOVANCE",
                    Style::default().fg(MINT).add_modifier(Modifier::BOLD),
                ),
                Span::styled(
                    format!("   /   RUST PREVIEW {}", env!("CARGO_PKG_VERSION")),
                    Style::default().fg(MUTED),
                ),
            ]),
            Line::from(format!(" {}", model::label(title))),
        ])
        .block(block("")),
        rows[0],
    );
    let hint = match body.map(|(_, mode)| mode) {
        None => "↑/↓ выбор  Enter открыть  Esc назад  F1 справка  Home/End  PgUp/PgDn",
        Some(BodyMode::Text) => "↑/↓ прокрутка  PgUp/PgDn страница  Enter/Esc закрыть",
        Some(BodyMode::Input) => "Enter отправить  Esc отменить",
        Some(BodyMode::Busy) => {
            "Дождись результата. Ctrl+C прерывает процесс; возможны частичные изменения."
        }
    };
    let footer = Paragraph::new(format!("{status}\n{hint}"))
        .wrap(Wrap { trim: false })
        .style(Style::default().fg(MUTED))
        .block(block(" Состояние "));
    f.render_widget(footer, rows[2]);
    if let Some((body, mode)) = body {
        let title = match mode {
            BodyMode::Text => " Подробности · Enter/Esc закрыть ",
            BodyMode::Input => " Ввод ответа ",
            BodyMode::Busy => " Выполняется · вывод движка ",
        };
        f.render_widget(
            Paragraph::new(model::clean(body))
                .wrap(Wrap { trim: false })
                .scroll((scroll, 0))
                .block(block(title)),
            rows[1],
        );
        return;
    }
    let panes = if rows[1].width >= 90 {
        Layout::default()
            .direction(Direction::Horizontal)
            .constraints([Constraint::Percentage(46), Constraint::Percentage(54)])
            .split(rows[1])
    } else {
        Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(55), Constraint::Percentage(45)])
            .split(rows[1])
    };
    let items = entries
        .iter()
        .map(|entry| {
            let text = model::label(&entry.text);
            let style = if entry.selectable {
                Style::default().fg(TEXT)
            } else {
                Style::default().fg(MINT).add_modifier(Modifier::BOLD)
            };
            ListItem::new(text).style(style)
        })
        .collect::<Vec<_>>();
    let list = List::new(items)
        .block(block(" Разделы "))
        .highlight_symbol("› ")
        .highlight_style(
            Style::default()
                .bg(Color::Rgb(27, 70, 68))
                .fg(Color::Rgb(101, 255, 218))
                .add_modifier(Modifier::BOLD),
        );
    let mut state = ListState::default().with_selected(selection);
    f.render_stateful_widget(list, panes[0], &mut state);
    let help = selection
        .and_then(|s| entries.get(s))
        .map(|e| e.help.lines())
        .unwrap_or_default();
    f.render_widget(
        Paragraph::new(help)
            .wrap(Wrap { trim: false })
            .block(block(" Что изменится · F1 полное описание ")),
        panes[1],
    );
}
fn input_frame(f: &mut Frame, title: &str, context: &str, input: &str, scroll: u16) {
    frame(
        f,
        title,
        &[],
        None,
        "Enter отправить · Esc отменить · PgUp/PgDn контекст",
        Some(("", BodyMode::Input)),
        0,
    );
    let body = screen_areas(f.area())[1];
    let parts = Layout::default()
        .direction(Direction::Vertical)
        .constraints([Constraint::Min(0), Constraint::Length(3)])
        .split(body);
    f.render_widget(
        Paragraph::new(model::clean(context))
            .wrap(Wrap { trim: false })
            .scroll((scroll, 0))
            .block(block(" Контекст · PgUp/PgDn ")),
        parts[0],
    );
    let field = block(" Ответ ").border_style(Style::default().fg(MINT));
    let width = field.inner(parts[1]).width;
    let line = format!("> {}▏", model::clean(input));
    let offset = UnicodeWidthStr::width(line.as_str()).saturating_sub(width as usize) as u16;
    f.render_widget(
        Paragraph::new(line)
            .scroll((0, offset))
            .block(field)
            .style(Style::default().fg(MINT)),
        parts[1],
    );
}

struct ScreenGuard;
impl Drop for ScreenGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, crossterm::cursor::Show);
    }
}
pub struct Ui {
    terminal: Terminal<CrosstermBackend<Stdout>>,
    _guard: ScreenGuard,
}
impl Ui {
    pub fn new() -> Result<Self> {
        if !io::stdin().is_terminal() || !io::stdout().is_terminal() {
            bail!("Нужен интерактивный терминал. Для просмотра без ввода используй --snapshot.");
        }
        enable_raw_mode()?;
        let guard = ScreenGuard;
        execute!(io::stdout(), EnterAlternateScreen)?;
        let terminal = Terminal::new(CrosstermBackend::new(io::stdout()))?;
        Ok(Self {
            terminal,
            _guard: guard,
        })
    }
    pub fn choose(
        &mut self,
        title: &str,
        entries: &[Entry],
        status: &str,
    ) -> Result<Option<usize>> {
        self.choose_at(title, entries, status, None)
    }
    pub fn choose_at(
        &mut self,
        title: &str,
        entries: &[Entry],
        status: &str,
        selected: Option<usize>,
    ) -> Result<Option<usize>> {
        let mut state = Selection::default();
        state.restore(entries, selected);
        loop {
            self.terminal
                .draw(|f| frame(f, title, entries, state.selected, status, None, 0))?;
            if !event::poll(std::time::Duration::from_millis(100))? {
                continue;
            }
            let Event::Key(key) = event::read()? else {
                continue;
            };
            if key.kind == KeyEventKind::Release {
                continue;
            }
            if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
                bail!("Остановлено пользователем");
            }
            match key.code {
                KeyCode::Down => state.step(entries, 1),
                KeyCode::Up => state.step(entries, -1),
                KeyCode::PageDown => state.page(entries, 8),
                KeyCode::PageUp => state.page(entries, -8),
                KeyCode::Home => state.edge(entries, false),
                KeyCode::End => state.edge(entries, true),
                KeyCode::Esc => return Ok(None),
                KeyCode::Enter if key.kind == KeyEventKind::Press => {
                    return Ok(state.selected.map(|s| entries[s].index))
                }
                KeyCode::F(1) => {
                    if let Some(entry) = state.selected.and_then(|s| entries.get(s)) {
                        self.text(&entry.text, &entry.help.lines(), status)?;
                    }
                }
                _ => (),
            }
        }
    }
    pub fn text(&mut self, title: &str, text: &str, status: &str) -> Result<()> {
        let mut scroll = 0u16;
        loop {
            self.terminal.draw(|f| {
                frame(
                    f,
                    title,
                    &[],
                    None,
                    status,
                    Some((text, BodyMode::Text)),
                    scroll,
                )
            })?;
            if !event::poll(std::time::Duration::from_millis(100))? {
                continue;
            }
            let Event::Key(key) = event::read()? else {
                continue;
            };
            if key.kind == KeyEventKind::Release {
                continue;
            }
            match key.code {
                KeyCode::Enter | KeyCode::Esc => return Ok(()),
                KeyCode::Down => scroll = scroll.saturating_add(1),
                KeyCode::Up => scroll = scroll.saturating_sub(1),
                KeyCode::PageDown => scroll = scroll.saturating_add(12),
                KeyCode::PageUp => scroll = scroll.saturating_sub(12),
                KeyCode::Home => scroll = 0,
                KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    bail!("Остановлено пользователем")
                }
                _ => (),
            }
        }
    }
    pub fn input(&mut self, title: &str, context: &str) -> Result<Option<String>> {
        let mut input = String::new();
        let mut scroll = 0u16;
        loop {
            self.terminal
                .draw(|f| input_frame(f, title, context, &input, scroll))?;
            let Event::Key(key) = event::read()? else {
                continue;
            };
            if key.kind == KeyEventKind::Release {
                continue;
            }
            match key.code {
                KeyCode::Enter if key.kind == KeyEventKind::Press => return Ok(Some(input)),
                KeyCode::Esc => return Ok(None),
                KeyCode::PageUp => scroll = scroll.saturating_sub(8),
                KeyCode::PageDown => scroll = scroll.saturating_add(8),
                KeyCode::Home => scroll = 0,
                KeyCode::Backspace => {
                    input.pop();
                }
                KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                    bail!("Остановлено пользователем")
                }
                KeyCode::Char(c)
                    if !key.modifiers.contains(KeyModifiers::CONTROL) && input.len() < 8192 =>
                {
                    input.push(c)
                }
                _ => (),
            }
        }
    }
    pub fn busy(&mut self, title: &str, lines: &[String], status: &str) -> Result<()> {
        let height = self.terminal.size()?.height.saturating_sub(13) as usize;
        let start = lines.len().saturating_sub(height.max(1));
        self.terminal.draw(|f| {
            frame(
                f,
                title,
                &[],
                None,
                status,
                Some((&lines[start..].join("\n"), BodyMode::Busy)),
                0,
            )
        })?;
        if event::poll(std::time::Duration::from_millis(40))? {
            if let Event::Key(key) = event::read()? {
                if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('c') {
                    bail!("Прервано пользователем; возможны частичные изменения. Проверь журнал.");
                }
            }
        }
        Ok(())
    }
}
pub fn snapshot(width: u16, height: u16) -> Result<String> {
    let width = width.clamp(40, 240);
    let height = height.clamp(12, 100);
    let backend = TestBackend::new(width, height);
    let mut terminal = Terminal::new(backend)?;
    let entries = crate::model::catalog();
    terminal.draw(|f| {
        frame(
            f,
            "Exovance Optimizer",
            &entries,
            Some(0),
            "ДЕМОНСТРАЦИЯ · настройки не изменяются",
            None,
            0,
        )
    })?;
    let buffer = terminal.backend().buffer();
    let mut out = String::new();
    for y in 0..height {
        for x in 0..width {
            out.push_str(buffer[(x, y)].symbol());
        }
        out.push('\n');
    }
    Ok(out)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tiny_and_large_frames_render_without_overflow_or_changes() {
        for (w, h) in [(40, 12), (80, 30), (120, 38), (240, 100)] {
            let text = snapshot(w, h).unwrap();
            assert_eq!(text.lines().count(), h as usize);
            assert!(text.contains("EXOVANCE"));
        }
    }
    #[test]
    fn f1_view_renders_long_registry_paths_and_unicode() {
        let mut t = Terminal::new(TestBackend::new(80, 30)).unwrap();
        let body = "HKLM\\Пример\\Путь 🦋\n".repeat(200);
        t.draw(|f| {
            frame(
                f,
                "Справка",
                &[],
                None,
                "Просмотр",
                Some((&body, BodyMode::Text)),
                25,
            )
        })
        .unwrap();
    }
    #[test]
    fn answer_stays_visible_with_a_long_prompt_and_unicode() {
        let mut t = Terminal::new(TestBackend::new(80, 20)).unwrap();
        let context = "Очень длинное описание изменений и путей реестра.\n".repeat(100);
        for answer in [
            "ПРИМЕНИТЬ".to_string(),
            format!("{}КОНЕЦ", "界".repeat(200)),
        ] {
            t.draw(|f| input_frame(f, "Подтверждение", &context, &answer, 40))
                .unwrap();
            let buffer = t.backend().buffer();
            let lines = (0..20)
                .map(|y| (0..80).map(|x| buffer[(x, y)].symbol()).collect::<String>())
                .collect::<Vec<_>>();
            let visible = lines.join("\n");
            assert!(visible.contains("Ответ"));
            assert!(visible.contains("▏"));
            assert!(visible.contains(if answer.ends_with("КОНЕЦ") {
                "КОНЕЦ"
            } else {
                "ПРИМЕНИТЬ"
            }));
        }
    }
}
