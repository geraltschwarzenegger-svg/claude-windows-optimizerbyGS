# 📚 Комплект, проверки и помощь

[← README](../README.md) · [Сетевые твики](NETWORK-TWEAKS.md)

## 📦 Комплект и дополнительные файлы Resources

В репозиторий уже добавлены **Device Tweaker** и **схема питания**. Для них v2 сначала проверяет прежний путь `Resources\…`, затем соответствующий путь в корне проекта. Остальные инструменты ожидаются в папке **`Resources` рядом с CMD**. Переименование произвольного EXE не делает его подходящим ресурсом.

```text
claude-windows-optimizerbyGS/
├── Low-Latency-Corp-Menu_SPI_24H2_VisualizationFix.cmd  ← оригинал
├── Low-Latency-Corp-Menu_v2.cmd                        ← новая версия
├── README.md
├── DEVICE-TWEAKER/                                    ← включённый инструмент
│   ├── RUN-DEVICE-TWEAKER.bat
│   └── DEVICE-TWEAKER-UPDATE-2026-LLG-X-LLC-UPDATED.ps1
├── POWER-PLAN/
│   └── LLC-CERTIFIED.pow                              ← включённая схема
├── docs/
├── tests/
└── Resources/                                         ← отдельно, отсутствует в репозитории
    ├── POWER-PLAN/
    │   └── LLC-CERTIFIED.pow
    └── NVIDIA-PROFILE-INSPECTOR/
        ├── NVIDIA-PROFILE-INSPECTOR.exe
        └── LLC-OPTIMIZED-V3.nip
```

<details>
<summary><b>🧰 Примеры путей для внешних приложений</b></summary>

| Пункт | Ожидаемый путь относительно CMD |
| :--- | :--- |
| Device Tweaker | `Resources\DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat` |
| Windows Defender Switcher | `Resources\WINDOWS-DEFENDER\RUN-WDS.bat` |
| Windows Update Blocker | `Resources\WINDOWS-UPDATES\RUN-WUB.bat` |
| HIDUSBF | `Resources\HIDUSBF\DRIVER\SETUP.exe` |
| 7-Zip | `Resources\7ZIP\7-Zip.exe` |
| Chrome | `Resources\CHROME\Chrome.exe` |
| Power Scheme Manager | `Resources\POWER-SCHEME-MANAGER\POWER-SCHEME-MANAGER.exe` |
| PresentMon CSV Plotter | `Resources\PRESENTMON-CSV-PLOTTER\PRESENTMON-CSV-PLOTTER.exe` |

Это часть ожидаемых путей. Для Device Tweaker v2 также использует включённый `DEVICE-TWEAKER\RUN-DEVICE-TWEAKER.bat`. Точные пути установщиков драйверов заданы в исходнике. Остальные перечисленные приложения не включены. Необязательный `pci.ids` рядом с CMD используется для уточнения названий GPU; справочник в `DEVICE-TWEAKER` относится к отдельному инструменту.

</details>

### 🔌 Что делает Device Tweaker

Это отдельный PowerShell-инструмент с графическим интерфейсом и собственным launcher. Он работает с MSI/MessageLimit, IRQ affinity/priority, RSS и параметрами устройств PCIe, USB и NVMe. Его наличие и запуск из меню не подтверждают полезность настроек для конкретного ПК.

В каталоге `RWEVERYTHING` есть установщик и REG-файлы. REG-файл `Apply-To-Fix-RWE-Driver-Loading.reg` отключает блокировку уязвимых драйверов, VBS/HVCI и связанные параметры защиты; **его импорт не является шагом установки этого обновления**. `RESET.reg` выставляет заданные автором значения, а не восстанавливает конфигурацию вашего ПК. Обработка RWEverything для NVMe по умолчанию отключена параметром `DisableRWEnNVMe`.

Существующие `device_settings_backup.json` и `logs/logging.txt` загружены вместе с инструментом. Это не резервная копия вашей системы; для восстановления нужны собственные данные, созданные на своём ПК.

## ↩️ Обратимость настроек

**Enable / Disable / Revert не равны восстановлению вашей прежней конфигурации.** Эти пункты часто записывают предопределённые значения или удаляют параметры. Например, Services возвращает встроенные типы запуска, а Network Disable удаляет используемые параметры, не сохраняя их прежние значения.

У менеджера автозагрузки есть собственные механизмы сохранения отключённых записей и ярлыков. Они относятся только к автозагрузке и не являются резервной копией Windows.

Скрипт не создаёт полный бэкап, не обеспечивает транзакционный откат и не восстанавливает автоматически успешно выполненные шаги после ошибки. Часть изменений требует выхода из сеанса или перезагрузки.

## 🧪 Проверка кода

Проверки новой логики запускаются без Pester и сторонних модулей:

```powershell
powershell.exe -NoProfile -File .\tests\Test-V2.ps1
powershell.exe -NoProfile -File .\tests\Test-Menu.ps1
```

Для статических проверок в Linux можно использовать PowerShell 7:

```sh
pwsh -NoProfile -File ./tests/Test-V2.ps1
pwsh -NoProfile -File ./tests/Test-Menu.ps1
```

Проверяется разбор обоих CMD-payload, подтверждения и отмена, границы размера загрузки, поиск включённых ресурсов и ранний выход режима проверки. Тесты не применяют твики Windows. Добавлен workflow GitHub Actions для Linux и Windows PowerShell 5.1; результат Windows CI следует смотреть в разделе Actions.

| 🟢 Пройдено | 🟡 Пропущено | 🖥️ Среда проверки |
| :---: | :---: | :---: |
| **68 проверок** | **3 проверки CMD в Windows** | Linux · PowerShell 7.4.13 |

**Граница проверки:** новая логика проверена локально в Linux с PowerShell 7.4.13 и в GitHub Actions с Windows PowerShell 5.1, включая CMD `/help` и `/check`. Интерактивное меню, реестр, службы, драйверы и применение настроек требуют отдельного испытания на целевой Windows. Прохождение CI не подтверждает пользу твиков или их совместимость с вашим ПК.

## 🩺 Если что-то пошло не так

| Симптом | Что проверить |
| :--- | :--- |
| Требуются права администратора | Запустите CMD через «Запуск от имени администратора». |
| `/check` сообщает о неподходящем PowerShell | Используйте 64-битный **Windows PowerShell 5.1**, а не `pwsh`. |
| Не найден EXE / BAT / POW / NIP | Проверьте наличие ресурса и точное имя файла рядом с CMD. |
| Загрузка драйвера не удалась | URL фиксирован; проверьте доступность файла на официальном сайте производителя. |
| Часть защищённых ключей не изменилась | Изучите вывод, права и ошибку инициализации TrustedInstaller. Не считайте пакет применённым целиком. |
| Внешний вид не изменился сразу | Часть настроек применяется после повторного входа или перезагрузки. |

При обычном запуске отладочный журнал сохраняется в:

```text
%TEMP%\LowLatencyCorpMenu_Debug_<random>_<random>.log
```

При ошибке launcher показывает путь к журналу; `/check` завершается до запуска записи журнала. Перед публикацией лога просмотрите его: он может содержать имена пользователей и локальные пути.
