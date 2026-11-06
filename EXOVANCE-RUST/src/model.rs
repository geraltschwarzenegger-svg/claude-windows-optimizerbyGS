use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[serde(default, rename_all = "PascalCase")]
pub struct Help {
    pub summary: String,
    pub effect: String,
    pub r#where: String,
    pub recommendation: String,
    pub details: Vec<String>,
    pub registry_lines: Vec<String>,
}
impl Help {
    pub fn lines(&self) -> String {
        format!(
            "Что: {}\n\nДействие: {}\n\nГде: {}\n\nСовет: {}\n\n{}\n{}",
            self.summary,
            self.effect,
            self.r#where,
            self.recommendation,
            self.details.join("\n"),
            self.registry_lines.join("\n")
        )
    }
}
#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct Entry {
    pub index: usize,
    pub text: String,
    pub selectable: bool,
    #[serde(default)]
    pub value: Value,
    #[serde(default)]
    pub help: Help,
}
impl Entry {
    pub fn action(index: usize, text: &str, value: &str) -> Self {
        Self {
            index,
            text: text.into(),
            selectable: true,
            value: Value::String(value.into()),
            help: Help::default(),
        }
    }
}
#[derive(Clone, Debug, Default, Deserialize)]
#[serde(default)]
pub struct Request {
    pub kind: String,
    pub id: u64,
    pub title: String,
    pub level: String,
    pub entries: Vec<Entry>,
}
#[derive(Debug, Default, Serialize)]
pub struct Reply {
    pub id: u64,
    pub index: usize,
    pub text: String,
    pub cancelled: bool,
}

pub fn catalog() -> Vec<Entry> {
    serde_json::from_str(include_str!("../assets/catalog.json"))
        .expect("validated embedded catalog")
}
pub fn clean(text: &str) -> String {
    text.chars()
        .filter(|c| !c.is_control() || *c == '\n' || *c == '\t')
        .collect()
}
pub fn label(text: &str) -> String {
    let translated = match text {
        "Preflight / About v2" => "О программе и проверка",
        "System and registry" => "СИСТЕМА И РЕЕСТР",
        "Auto Registry Tweaks" => "Автоматическая оптимизация",
        "Drivers and apps" => "ДРАЙВЕРЫ И ПРИЛОЖЕНИЯ",
        "Other" => "ДОПОЛНИТЕЛЬНО",
        "Services" => "Службы",
        "Powersaving" => "Энергосбережение устройств",
        "Network Optimization" => "Настройки сети",
        "Apps" => "Приложения",
        "Drivers" => "Драйверы",
        "Autostart" => "Автозагрузка",
        "Power Plan" => "Схемы питания",
        "Activate Windows" => "Активация Windows",
        "Exit" => "Выход",
        "Back" => "Назад",
        "Enable" => "Включить",
        "Disable" => "Выключить",
        "Launch Exovance v2" => "Открыть Exovance Device Tweaker v2",
        other => other,
    };
    clean(translated)
}

#[derive(Default)]
pub struct Selection {
    pub selected: Option<usize>,
}
impl Selection {
    pub fn reset(&mut self, entries: &[Entry]) {
        self.selected = entries.iter().position(|x| x.selectable);
    }
    pub fn step(&mut self, entries: &[Entry], delta: isize) {
        let positions: Vec<_> = entries
            .iter()
            .enumerate()
            .filter(|(_, e)| e.selectable)
            .map(|(i, _)| i)
            .collect();
        if positions.is_empty() {
            self.selected = None;
            return;
        }
        let current = positions
            .iter()
            .position(|&i| Some(i) == self.selected)
            .unwrap_or(0);
        let next = (current as isize + delta).rem_euclid(positions.len() as isize) as usize;
        self.selected = Some(positions[next]);
    }
    pub fn page(&mut self, entries: &[Entry], delta: isize) {
        let positions: Vec<_> = entries
            .iter()
            .enumerate()
            .filter(|(_, e)| e.selectable)
            .map(|(i, _)| i)
            .collect();
        if positions.is_empty() {
            self.selected = None;
            return;
        }
        let current = positions
            .iter()
            .position(|&i| Some(i) == self.selected)
            .unwrap_or(0);
        let next = (current as isize + delta).clamp(0, positions.len() as isize - 1) as usize;
        self.selected = Some(positions[next]);
    }
    pub fn edge(&mut self, entries: &[Entry], last: bool) {
        self.selected = if last {
            entries.iter().rposition(|x| x.selectable)
        } else {
            entries.iter().position(|x| x.selectable)
        };
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn selection_skips_headers_and_wraps() {
        let entries = catalog();
        let mut s = Selection::default();
        s.reset(&entries);
        assert_eq!(entries[s.selected.unwrap()].value, "preflight");
        s.step(&entries, 1);
        assert_eq!(entries[s.selected.unwrap()].value, "autoRegistryTweaks");
        s.edge(&entries, true);
        s.page(&entries, 8);
        assert_eq!(entries[s.selected.unwrap()].value, "exit");
        s.step(&entries, 1);
        assert_eq!(entries[s.selected.unwrap()].value, "preflight");
    }
    #[test]
    fn empty_menu_and_headers_are_not_actions() {
        let mut entries = catalog();
        entries.iter_mut().for_each(|e| e.selectable = false);
        let mut s = Selection::default();
        s.step(&entries, -1);
        assert_eq!(s.selected, None);
    }
    #[test]
    fn all_legacy_sections_have_help_and_unique_routes() {
        let entries = catalog();
        let actions: Vec<_> = entries.iter().filter(|e| e.selectable).collect();
        assert_eq!(actions.len(), 20);
        let unique: std::collections::HashSet<_> =
            actions.iter().map(|e| e.value.as_str().unwrap()).collect();
        assert_eq!(unique.len(), actions.len());
        assert!(actions
            .iter()
            .all(|e| !e.help.summary.is_empty() && !e.help.r#where.is_empty()));
    }
    #[test]
    fn device_text_cannot_inject_terminal_escape_sequences() {
        assert_eq!(clean("GPU\x1b[2J\x07\r"), "GPU[2J");
    }
}
