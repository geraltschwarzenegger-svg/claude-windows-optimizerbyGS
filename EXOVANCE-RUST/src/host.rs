use anyhow::{bail, Context, Result};
use std::{
    path::{Path, PathBuf},
    process::{Command, Output},
};

pub fn system_program(name: &str) -> Result<PathBuf> {
    if !cfg!(windows) {
        bail!("Для этого действия нужна Windows x64. Просмотр: --demo или --snapshot.");
    }
    let windows = std::env::var_os("SystemRoot").context("SystemRoot отсутствует")?;
    Ok(PathBuf::from(windows).join("System32").join(name))
}
pub fn powershell() -> Result<PathBuf> {
    system_program("WindowsPowerShell/v1.0/powershell.exe")
}
pub fn require_windows() -> Result<()> {
    if !cfg!(all(windows, target_pointer_width = "64")) {
        bail!("Изменение настроек доступно только в Windows x64. Используй --demo для просмотра.");
    }
    Ok(())
}
#[cfg(windows)]
pub fn is_admin() -> bool {
    use windows_sys::Win32::Security::{
        AllocateAndInitializeSid, CheckTokenMembership, FreeSid, SID_IDENTIFIER_AUTHORITY,
    };
    let authority = SID_IDENTIFIER_AUTHORITY {
        Value: [0, 0, 0, 0, 0, 5],
    };
    let mut sid = std::ptr::null_mut();
    let mut member = 0;
    // SID S-1-5-32-544 is BUILTIN\Administrators; a filtered UAC token does not satisfy it.
    unsafe {
        if AllocateAndInitializeSid(&authority, 2, 32, 544, 0, 0, 0, 0, 0, 0, &mut sid) == 0 {
            return false;
        }
        let ok = CheckTokenMembership(std::ptr::null_mut(), sid, &mut member);
        FreeSid(sid);
        ok != 0 && member != 0
    }
}
#[cfg(not(windows))]
pub fn is_admin() -> bool {
    false
}
#[cfg(windows)]
fn decode(bytes: &[u8]) -> String {
    use windows_sys::Win32::Globalization::{MultiByteToWideChar, CP_OEMCP};
    if let Ok(text) = std::str::from_utf8(bytes) {
        return text.to_string();
    }
    unsafe {
        let length = MultiByteToWideChar(
            CP_OEMCP,
            0,
            bytes.as_ptr(),
            bytes.len() as i32,
            std::ptr::null_mut(),
            0,
        );
        if length <= 0 {
            return String::from_utf8_lossy(bytes).into_owned();
        }
        let mut out = vec![0u16; length as usize];
        MultiByteToWideChar(
            CP_OEMCP,
            0,
            bytes.as_ptr(),
            bytes.len() as i32,
            out.as_mut_ptr(),
            length,
        );
        String::from_utf16_lossy(&out)
    }
}
#[cfg(not(windows))]
fn decode(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).into_owned()
}
pub fn output_text(output: &Output) -> String {
    format!("{}{}", decode(&output.stdout), decode(&output.stderr))
}
pub fn run(program: &str, args: &[String]) -> Result<String> {
    require_windows()?;
    let output = Command::new(system_program(program)?).args(args).output()?;
    let text = output_text(&output);
    if !output.status.success() {
        bail!("{program}: код {:?}: {text}", output.status.code());
    }
    Ok(text)
}
pub fn resolve_root(explicit: Option<&Path>) -> Result<PathBuf> {
    if let Some(path) = explicit {
        return dunce::canonicalize(path).context("Каталог --root не найден");
    }
    let exe = std::env::current_exe()?;
    for candidate in exe
        .parent()
        .into_iter()
        .chain(std::env::current_dir().ok().as_deref())
    {
        for path in candidate.ancestors().take(5) {
            if path.join("DEVICE-TWEAKER-V2").is_dir() && path.join("POWER-PLAN").is_dir() {
                return Ok(path.to_path_buf());
            }
        }
    }
    Ok(exe
        .parent()
        .context("Нет каталога программы")?
        .to_path_buf())
}
pub fn resolve_resource(root: &Path, relative: &str, bundled: Option<&str>) -> Result<PathBuf> {
    let preferred = root.join(relative);
    if preferred.is_file() {
        return Ok(preferred);
    }
    if let Some(fallback) = bundled {
        let path = root.join(fallback);
        if path.is_file() {
            return Ok(path);
        }
    }
    bail!(
        "Нет файла {}. Укажи каталог комплекта через --root.",
        preferred.display()
    )
}
