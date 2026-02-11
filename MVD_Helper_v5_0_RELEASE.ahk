; ==============================================================================
; МВД Helper v5.0 — AHK v1.1 Unicode — RELEASE
; На базе Rivera & Deep (RP-тексты, погоны, пол) + ядро v4.3 (стабильность)
; ==============================================================================
; Changelog v5.0 (Rivera merge):
;   [MERGE] Движок v4.3 (Guard/Release/SafeMode/SendChat/profiles/DiagTip)
;   [MERGE] RP-тексты Rivera: приветствие+погоны, мегафон (СГУ), крики, розыск,
;           конвоирование, КПЗ, планшет, обыск, наручники, документы, рация
;   [NEW]  Профиль: GreetingStyle (Здравия желаю/Здравствуйте), Gender (М/Ж)
;   [NEW]  Погоны: автоматическое описание по званию (PogonLine)
;   [NEW]  Гендерные окончания глаголов (Rivera: ok1..ok9)
;   [NEW]  Расширенный список званий (от Рядового до Генерала МВД)
;   [FIX]  Rivera баги: SendPlay{F8}→SendChat(), *uiAccess→убрано,
;          CheckAdmin→убрано, Wanted→через InputBox+/su, обыск пунктуация,
;          "15 метров"→"15 метров", Alt+3/4/5→работают через Seq
;   [KEEP] Всё из v4.3: Guard busy+cooldown, SafeMode buffer, DiagTip,
;          forceChatKeyNoMods physical check, chatKey validation, Release order
;
; Запуск:
;   1. AutoHotkey v1.1 Unicode (32/64-бит)
;   2. Положить .ahk в любую папку
;   3. profiles.ini создастся автоматически (UTF-16 LE)
;   4. Если MTA от админа → запускать скрипт тоже от админа
;   5. Alt+M — профиль, Pause — пауза, Ctrl+Pause — SafeMode
; ==============================================================================

#NoEnv
#SingleInstance Force
#MaxThreadsPerHotkey 1
#InstallKeybdHook
#UseHook On
#KeyHistory 0
ListLines, Off
SendMode Event
SetBatchLines, 10ms
SetWorkingDir %A_ScriptDir%
SetDefaultMouseSpeed 0
SetTitleMatchMode, 2

; ==============================================================================
; ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
; ==============================================================================
global VERSION := "5.0"
global iniFile := "profiles.ini"

global currentProfile := {}
global selectedOriginalName := ""
global busy := false
global lastActionTime := 0
global safeModeLines := []

; Кэш IsGameActive()
global gameActiveCache := false
global gameActiveCacheTime := 0
global CACHE_TTL := 50

; Конфигурация (дефолты Win11 24H2)
global cfg := {}
cfg.chatKey          := "t"
cfg.cdMs             := 1500
cfg.chatOpenDelay    := 350
cfg.afterTypeDelay   := 100
cfg.seqMin           := 400
cfg.seqMax           := 700
cfg.releaseAltOnly   := 1
cfg.forceChatKeyNoMods := 0
cfg.sendMethod       := "Event"
cfg.safeMode         := 0
cfg.gameExeList      := "gta_sa.exe|Multi Theft Auto.exe"
cfg.enableLog        := 0

global gameExes   := []
global sectionSet := {}

; Гендерные окончания (Rivera): М=мужской, Ж=женский
; ok1: достал/достала, ok2: поднёс/поднесла, ok3: -ся/-ась
global gOk1 := ""    ; "" / "а"
global gOk2 := ""    ; "" / "ла"
global gOk3 := "ся"  ; "ся" / "ась"

; ==============================================================================
; ИНИЦИАЛИЗАЦИЯ
; ==============================================================================
EnsureIniExists()
LoadConfig()
ParseGameExeList()
UpdateSectionCache()
LoadActiveProfile()
DiagnosePrivileges()

if (currentProfile.Rank == "") {
    Gosub, ShowGui
} else {
    nm := currentProfile.Rank . " " . currentProfile.Surname
    TrayTip, МВД Helper v%VERSION%, Профиль: %nm%, 2, 1
}
return

; ==============================================================================
; ДИАГНОСТИКА ПРИВИЛЕГИЙ
; ==============================================================================
DiagnosePrivileges() {
    global gameExes, VERSION
    if (!A_IsAdmin)
        return
    for _, ex in gameExes {
        if WinExist("ahk_exe " . ex)
            return
    }
    TrayTip, МВД Helper v%VERSION%,
        (LTrim
            Скрипт запущен от администратора.
            Если MTA запущена обычно — перезапустите скрипт без прав админа.
        ), 5, 2
    LogWrite("WARN: script is admin but game not found")
}

; ==============================================================================
; GUI: МЕНЕДЖЕР ПРОФИЛЕЙ
; ==============================================================================
ShowGui:
    Gui, Destroy
    Gui, New, +AlwaysOnTop +HwndhGui +MinSize600x560
    Gui, Color, 181C25, 232832
    Gui, Font, s10 cWhite, Segoe UI

    ; === Левая колонка: список профилей ===
    Gui, Add, Text, x20 y15 w200 cSilver, Список профилей:
    Gui, Add, ListView, vProfileList gOnProfileSelect x20 y40 w180 h360 -Multi -Hdr Background2E3440 cWhite Border AltSubmit, Name

    Gui, Add, Button, gBtnAdd x20 y410 w50 h30, +
    Gui, Add, Button, gBtnDel x75 y410 w50 h30, -
    Gui, Add, Button, gBtnLoad x130 y410 w70 h30, Загрузить

    ; === Правая колонка: форма ===
    Gui, Font, s12 Bold
    Gui, Add, Text, x220 y15 w360 Center, Настройки профиля
    Gui, Font, s10 Norm

    yy := 50

    Gui, Add, Text, x220 y%yy% cSilver, Название профиля (для списка):
    yy += 20
    Gui, Add, Edit, vEditName x220 y%yy% w360 h25 Background2E3440 cWhite Border
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Приветствие:
    yy += 20
    Gui, Add, DropDownList, vEditGreeting x220 y%yy% w360 Choose1, Здравия желаю|Здравствуйте
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Организация:
    yy += 20
    Gui, Add, DropDownList, vEditStruct x220 y%yy% w360 Choose1, УВД|ГИБДД
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Звание:
    yy += 20
    Gui, Add, DropDownList, vEditRank x220 y%yy% w360 Choose1, Рядовой|Сержант|Старшина|Прапорщик|Лейтенант|Старший лейтенант|Капитан|Майор|Подполковник|Полковник|Генерал-майор|Генерал-лейтенант|Генерал-полковник|Генерал МВД
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Фамилия:
    yy += 20
    Gui, Add, Edit, vEditSurname x220 y%yy% w360 h25 Background2E3440 cWhite Border
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Должность:
    yy += 20
    Gui, Add, Edit, vEditPost x220 y%yy% w360 h25 Background2E3440 cWhite Border
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Город/район (напр. г. Невский):
    yy += 20
    Gui, Add, Edit, vEditDept x220 y%yy% w360 h25 Background2E3440 cWhite Border
    yy += 35

    Gui, Add, Text, x220 y%yy% cSilver, Пол (для окончаний глаголов):
    yy += 20
    Gui, Add, DropDownList, vEditGender x220 y%yy% w360 Choose1, М|Ж
    yy += 40

    Gui, Font, s11 Bold
    Gui, Add, Button, gBtnSave x220 y%yy% w360 h40 Default, Сохранить

    RefreshList()
    title := "МВД Helper v" . VERSION
    Gui, Show, w600 h560, %title%
return

OnProfileSelect:
    if (A_GuiEvent == "DoubleClick") {
        Gosub, BtnLoad
        return
    }
    if (A_GuiEvent != "Normal" && A_GuiEvent != "I" && A_GuiEvent != "K")
        return
    Gui, ListView, ProfileList
    LV_GetText(dispName, A_EventInfo, 1)
    if (dispName == "")
        return
    realName := StripActiveMarker(dispName)
    selectedOriginalName := realName
    prof := ReadProfile(realName)
    FillForm(prof, realName)
return

BtnSave:
    Gui, Submit, NoHide

    newName := SanitizeProfileName(EditName)
    if (newName == "") {
        MsgBox, 48, Ошибка, Имя профиля пустое или содержит запрещённые символы.`n`nЗапрещено: [ ] = ; # переводы строк.`nМакс. длина: 50 символов.
        return
    }
    if (IsReservedSection(newName)) {
        MsgBox, 48, Ошибка, Имя "%newName%" зарезервировано. Выберите другое.
        return
    }

    UpdateSectionCache()
    isRename := (selectedOriginalName != "" && selectedOriginalName != newName)
    if (isRename || selectedOriginalName == "") {
        if (SectionExists(newName)) {
            MsgBox, 48, Ошибка, Профиль "%newName%" уже существует!
            return
        }
    }

    WriteProfile(newName, EditGreeting, EditStruct, EditRank, EditSurname, EditPost, EditDept, EditGender)

    ; Предупреждение: пустые ключевые поля
    warnFields := ""
    if (Trim(EditRank) == "")
        warnFields .= "• Звание`n"
    if (Trim(EditSurname) == "")
        warnFields .= "• Фамилия`n"
    if (warnFields != "") {
        MsgBox, 48, Внимание, Некоторые поля пустые — будут использованы дефолтные значения:`n`n%warnFields%
        LogWrite("WARN: empty fields in profile " . newName)
    }

    if (isRename) {
        IniDelete, %iniFile%, %selectedOriginalName%
        IniRead, activeNow, %iniFile%, Main, ActiveProfile, %A_Space%
        if (Trim(activeNow) == selectedOriginalName)
            IniWrite, %newName%, %iniFile%, Main, ActiveProfile
        LogWrite("Profile renamed: " . selectedOriginalName . " -> " . newName)
    }

    selectedOriginalName := newName
    IniWrite, %newName%, %iniFile%, Main, ActiveProfile
    LoadActiveProfile()
    RefreshList()
    GuiControl,, EditName, %newName%
    MsgBox, 64, Успех, Профиль сохранён и активирован.
    LogWrite("Profile saved: " . newName)
return

BtnAdd:
    UpdateSectionCache()
    baseName := "Новый_Профиль"
    newName := baseName
    count := 1
    while (SectionExists(newName)) {
        count++
        newName := baseName . "_" . count
    }
    ClearForm()
    GuiControl,, EditName, %newName%
    selectedOriginalName := ""
    GuiControl, Focus, EditName
return

BtnDel:
    Gui, ListView, ProfileList
    row := LV_GetNext(0, "F")
    if (!row)
        return
    LV_GetText(dispName, row, 1)
    realName := StripActiveMarker(dispName)
    if (realName == "")
        return
    MsgBox, 4, Удаление, Удалить профиль "%realName%"?
    IfMsgBox No
        return
    IniDelete, %iniFile%, %realName%
    IniRead, activeName, %iniFile%, Main, ActiveProfile, %A_Space%
    if (Trim(activeName) == realName) {
        IniWrite, %A_Space%, %iniFile%, Main, ActiveProfile
        currentProfile := {}
        LogWrite("Active profile deleted: " . realName)
    }
    selectedOriginalName := ""
    RefreshList()
    ClearForm()
return

BtnLoad:
    Gui, ListView, ProfileList
    row := LV_GetNext(0, "F")
    if (!row) {
        MsgBox, 48, Ошибка, Выберите профиль из списка!
        return
    }
    LV_GetText(dispName, row, 1)
    realName := StripActiveMarker(dispName)
    if (realName == "") {
        MsgBox, 48, Ошибка, Не удалось прочитать имя профиля.
        return
    }
    IniWrite, %realName%, %iniFile%, Main, ActiveProfile
    LoadActiveProfile()
    RefreshList()
    Gui, Hide
    nm := currentProfile.Rank . " " . currentProfile.Surname
    TrayTip, МВД Helper, Активен: %nm%, 2, 1
    LogWrite("Profile loaded: " . realName)
return

GuiClose:
    Gui, Hide
return

; ==============================================================================
; СИСТЕМНЫЕ ХОТКЕИ (работают всегда)
; ==============================================================================
Pause::
    Suspend
    state := A_IsSuspended ? "ПАУЗА" : "АКТИВЕН"
    TrayTip, МВД Helper, Скрипт: %state%, 2, 1
    LogWrite("Suspend toggled: " . state)
return

^Pause::
    if (busy) {
        TrayTip, МВД Helper, Дождитесь окончания отыгровки!, 1, 2
        return
    }
    cfg.safeMode := !cfg.safeMode
    IniWrite, % cfg.safeMode, %iniFile%, Config, SafeMode
    sm := cfg.safeMode ? "ON (без Enter, текст в буфер)" : "OFF"
    TrayTip, МВД Helper, SafeMode: %sm%, 2, 1
    LogWrite("SafeMode: " . sm)
return

^!r::
    if (busy) {
        TrayTip, МВД Helper, Дождитесь окончания отыгровки!, 1, 2
        return
    }
    LoadConfig()
    ParseGameExeList()
    UpdateSectionCache()
    LoadActiveProfile()
    TrayTip, МВД Helper, Конфиг перезагружен!, 2, 1
    LogWrite("Config reloaded")
return

!m::Gosub, ShowGui

; ==============================================================================
; RP БИНДЫ (только при фокусе игры)
; ==============================================================================
#If IsGameActive()

; --- Alt+1: Представиться + погон + /ud ID ---
; Rivera-стиль: приветствие → описание погон → /ud
!1::
    if (!Guard()) return
    try {
        p := currentProfile
        greeting := p.Greeting . "! " . p.Rank . " полиции " . p.Surname . ", " . p.Post . " " . p.Structure . " по " . p.DeptLine . "."
        pogon := GetPogonLine(p.Rank)
        lines := ["/say " . greeting]
        if (pogon != "")
            lines.Push("/do " . pogon)
        Seq(lines, 500, 800)
        SendChat("/ud ", false)
    } finally {
        Release()
    }
return

; --- Alt+2: Достать планшет ---
!2::
    if (!Guard()) return
    try {
        Seq(["/do Планшет марки ""T1 MAX"" находится в кармане сумки."
            ,"/me достав планшет из кармана и включил" . gOk1 . " его"], 500, 800)
    } finally {
        Release()
    }
return

; --- Alt+3: Убрать планшет ---
!3::
    if (!Guard()) return
    try {
        SendChat("/me заблокировал" . gOk1 . " планшет марки ""T1 MAX"" и убрал" . gOk1 . " в карман сумки")
    } finally {
        Release()
    }
return

; --- Alt+4: Установление личности (КПК) + /crimrec ---
!4::
    if (!Guard()) return
    try {
        Seq(["/me открыл" . gOk1 . " базу данных и ввёл" . gOk1 . " необходимые данные гражданского"
            ,"/do На экране высветилась необходимая информация о гражданине."], 600, 900)
        SendChat("/crimrec ", false)
    } finally {
        Release()
    }
return

; --- Alt+5: Розыск /su ID LVL REASON ---
!5::
    if (!Guard()) return
    try {
        id := AskDigits("ID гражданина для розыска:")
        if (id == "") return
        lvl := AskDigits("Уровень розыска (звёзды):", "3")
        if (lvl == "") return
        reason := AskReq("Статья/причина:", "6.1 УК РП")
        if (reason == "") return
        Seq(["/me сняв рацию с нагрудного кармана, связал" . gOk3 . " с оперативным дежурным и передал" . gOk1 . " ориентировку на гражданского"], 500, 700)
        SendChat("/su " . id . " " . lvl . " " . reason)
    } finally {
        Release()
    }
return

; --- Alt+6: Снять розыск /clear ---
!6::
    if (!Guard()) return
    try {
        Seq(["/me введя личные данные гражданина в базу данных, начал" . gOk1 . " поиск личного дела в БД МВД"
            ,"/do На экране высветилась информация о личном деле гражданина."
            ,"/me нажал" . gOk1 . " на дисплее кнопку ""аннулировать розыск гражданина"""], 600, 900)
        SendChat("/clear ", false)
    } finally {
        Release()
    }
return

; --- Alt+7: КПЗ /arrest (2 варианта) ---
!7::
    if (!Guard()) return
    try {
        res := Ask("1=У камеры, 2=Конвоиру на улице", "1")
        if (!res.ok) return
        v := Trim(res.val)
        if (v == "2") {
            Seq(["/say Товарищ конвоир, примите задержанного для помещения в камеру."
                ,"/do Конвоир подошёл к сотруднику и задержанному."
                ,"/me передал" . gOk1 . " задержанного конвоиру, после чего сделал" . gOk1 . " шаг назад"
                ,"/do Конвоир сопровождает задержанного в сторону камер временного содержания."], 600, 900)
        } else {
            Seq(["/do Ключ от камеры находится на тактическом поясе сотрудника."
                ,"/me снял" . gOk1 . " ключ с пояса, открыл" . gOk1 . " камеру и завёл" . gOk1 . " задержанного внутрь"
                ,"/todo Камера к вашим услугам, располагайтесь.*закрыл" . gOk1 . " камеру на ключ и повесил" . gOk1 . " его обратно на пояс"], 700, 1000)
        }
        SendChat("/arrest ", false)
    } finally {
        Release()
    }
return

; --- Alt+8: Конвоирование /arr ---
!8::
    if (!Guard()) return
    try {
        Seq(["/me заломив руки гражданину, повёл" . gOk1 . " его за собой"], 400, 600)
        SendChat("/arr ", false)
    } finally {
        Release()
    }
return

; --- Alt+9: Снять конвой /dearr ---
!9::
    if (!Guard()) return
    try {
        SendChat("/me отпустил" . gOk1 . " гражданина и снял" . gOk1 . " конвоирование")
        Sleep, 500
        SendChat("/dearr ", false)
    } finally {
        Release()
    }
return

; --- Alt+0: Посадить в авто /putpl ---
!0::
    if (!Guard()) return
    try {
        Seq(["/say Берегите голову при посадке в автомобиль!"
            ,"/me посадил" . gOk1 . " задержанного в служебный автомобиль и захлопнул" . gOk1 . " дверь"], 600, 900)
        SendChat("/putpl ", false)
    } finally {
        Release()
    }
return

; --- Alt+-: Высадить из авто /eject ---
!-::
    if (!Guard()) return
    try {
        SendChat("/eject ", false)
    } finally {
        Release()
    }
return

; --- Alt+=: Мегафон (СГУ) — Rivera стиль ---
; 1=Остановка, 2=Перед огнём, 3=Пропустите спецтранспорт
!=::
    if (!Guard()) return
    try {
        res := Ask("1=Остановка, 2=Перед огнём, 3=Пропуск спецтранспорта", "1")
        if (!res.ok) return
        v := Trim(res.val)
        if (v == "1") {
            Seq(["/me снял" . gOk1 . " рупор с крепления, зажал" . gOk1 . " кнопку и поднёс" . gOk1 . " его ко рту"
                ,"/m Водитель впередиидущего ТС, принимаем крайнее правое положение и останавливаемся!"
                ,"/me отжал" . gOk1 . " кнопку, повесив рупор обратно в крепление"], 400, 700)
        } else if (v == "2") {
            Seq(["/me снял" . gOk1 . " рупор с крепления, зажал" . gOk1 . " кнопку и поднёс" . gOk1 . " его ко рту"
                ,"/m Водитель впередиидущего ТС, немедленно остановить транспорт! В случае неповиновения — открываю огонь!"
                ,"/me отжал" . gOk1 . " кнопку, повесив рупор обратно в крепление"], 400, 700)
        } else if (v == "3") {
            Seq(["/me снял" . gOk1 . " рупор с крепления, зажал" . gOk1 . " кнопку и поднёс" . gOk1 . " его ко рту"
                ,"/m Прижимаемся к обочине и пропускаем специализированный транспорт МВД!"
                ,"/me отжал" . gOk1 . " кнопку, повесив рупор обратно в крепление"], 400, 700)
        }
    } finally {
        Release()
    }
return

; --- Alt+S: Крики /s ---
; 1=Стой, 2=Территория, 3=Покинуть авто
!s::
    if (!Guard()) return
    try {
        res := Ask("1=Стой, 2=Территория МВД, 3=Покинуть авто", "1")
        if (!res.ok) return
        v := Trim(res.val)
        if (v == "1")
            SendChat("/s Гражданин, немедленно остановитесь, или применяю меры воздействия!")
        else if (v == "2") {
            Seq(["/s Гражданин! Покидаем закрытую территорию МВД, в противном случае будете задержаны по 6.8 УК РП!"
                ,"/s Даю 10 секунд!"], 800, 1200)
        } else if (v == "3")
            SendChat("/s Покиньте автомобиль, иначе будете задержаны согласно 5.8 УК РП!")
    } finally {
        Release()
    }
return

; --- Alt+C: Наручники /cuff ---
!c::
    if (!Guard()) return
    try {
        Seq(["/me заломив руки гражданину, зафиксировал" . gOk1 . " их"
            ,"/do Руки гражданина зафиксированы."], 400, 600)
        SendChat("/cuff ", false)
    } finally {
        Release()
    }
return

; --- Alt+U: Снять наручники /uncuff ---
!u::
    if (!Guard()) return
    try {
        Seq(["/me снял" . gOk1 . " наручники с гражданина и убрал" . gOk1 . " их в подсумок"
            ,"/do Наручники сняты."], 400, 600)
        SendChat("/uncuff ", false)
    } finally {
        Release()
    }
return

; --- Alt+F: Обыск /search ---
; (Rivera fix: убрана лишняя точка, одна пара строк)
!f::
    if (!Guard()) return
    try {
        Seq(["/me надел" . gOk1 . " стерильные перчатки и начал" . gOk1 . " обыск"
            ,"/me прощупал" . gOk1 . " одежду и проверил" . gOk1 . " содержимое карманов"], 800, 1200)
        SendChat("/search ", false)
    } finally {
        Release()
    }
return

; --- Alt+P: Штраф /tsu ---
!p::
    if (!Guard()) return
    try {
        Seq(["/me ввёл" . gOk1 . " в базу данных данные о нарушении, нашёл" . gOk1 . " информацию о гражданине и выписал" . gOk1 . " штраф"
            ,"/say Штраф можете оплатить в ближайшем отделении банка или через мобильный телефон."], 600, 900)
        SendChat("/tsu ", false)
    } finally {
        Release()
    }
return

; --- Alt+R: Доклад по рации ---
!r::
    if (!Guard()) return
    try {
        res := Ask("1=Патруль начало, 2=Пост, 3=Конец", "1")
        if (res.ok) {
            p := currentProfile
            loc := p.DeptLine
            v := Trim(res.val)
            tag    := (v == "2") ? "Пост" : "Патруль"
            action := (v == "1") ? "Начинаю" : (v == "3" ? "Заканчиваю" : "Заступил" . gOk1 . " на")
            SendChat("/r [" . tag . "] Докладывает: " . p.Surname
                . ". " . action . " " . tag . ": " . loc . ". Состояние: стабильно.")
        }
    } finally {
        Release()
    }
return

; --- Alt+G: Проверка документов /pass или /lic ---
!g::
    if (!Guard()) return
    try {
        res := Ask("1=Паспорт (/pass), 2=В/У (/lic)", "1")
        if (!res.ok) return
        v := Trim(res.val)
        if (v == "2") {
            SendChat("/say Гражданин, предоставьте ваше водительское удостоверение для проверки.")
            Sleep, 500
            SendChat("/lic ", false)
        } else {
            SendChat("/say Гражданин, предоставьте документ, удостоверяющий Вашу личность.")
            Sleep, 500
            SendChat("/pass ", false)
        }
    } finally {
        Release()
    }
return

; --- Alt+V: Вернуть документы ---
!v::
    if (!Guard()) return
    try {
        Seq(["/me взяв документы из рук гражданина, принял" . gOk3 . " за изучение данных, представленных там"
            ,"/say Можете забирать свои документы."
            ,"/me передал" . gOk1 . " документы обратно человеку напротив"], 800, 1200)
    } finally {
        Release()
    }
return

; --- Alt+I: Установление личности через фото ---
!i::
    if (!Guard()) return
    try {
        Seq(["/me запустив камеру, сфотографировал" . gOk1 . " человека, после внёс" . gOk1 . " фотографию в базу данных"
            ,"/do На экране высветилась вся информация о человеке."], 600, 900)
        SendChat("/crimrec ", false)
    } finally {
        Release()
    }
return

; --- Alt+T: Рация (вкл/достать/убрать) ---
!t::
    if (!Guard()) return
    try {
        res := Ask("1=Вкл(смена), 2=Достать, 3=Убрать", "1")
        if (!res.ok) return
        v := Trim(res.val)
        if (v == "1") {
            Seq(["/me сняв рацию с нагрудного кармана, перевёл" . gOk1 . " её в режим прослушивания и повесил" . gOk1 . " на нагрудный карман"
                ,"/fracvoice 2"], 500, 700)
        } else if (v == "2") {
            Seq(["/me зажал" . gOk1 . " кнопку для переговоров и поднёс" . gOk1 . " рацию ко рту"
                ,"/fracvoice 1"], 400, 600)
        } else if (v == "3") {
            Seq(["/me повесил" . gOk1 . " рацию на нагрудный карман, отжав кнопку"
                ,"/fracvoice 2"], 400, 600)
        }
    } finally {
        Release()
    }
return

; --- Alt+X: Повалить на землю (Rivera) ---
!x::
    if (!Guard()) return
    try {
        SendChat("/me схватил" . gOk1 . " водителя за руку и повалил" . gOk1 . " его на землю!")
    } finally {
        Release()
    }
return

#If ; конец контекстных хоткеев

; ==============================================================================
; CORE: Guard / Release
; ==============================================================================
Guard() {
    global busy, lastActionTime, cfg, currentProfile, safeModeLines

    if (busy) {
        DiagTip("Занят (выполняется другой бинд)")
        return false
    }

    elapsed := A_TickCount - lastActionTime
    if (elapsed < cfg.cdMs) {
        remaining := cfg.cdMs - elapsed
        DiagTip("Кулдаун (" . remaining . "мс)")
        return false
    }

    if (!IsObject(currentProfile) || currentProfile.Rank == "") {
        TrayTip, МВД Helper, Профиль не загружен! Alt+M для настройки., 2, 2
        LogWrite("Guard BLOCKED: no profile")
        return false
    }

    if (!IsGameActive()) {
        DiagTip("Игра не в фокусе")
        return false
    }

    busy := true
    safeModeLines := []
    LogWrite("Guard OK: action started")
    return true
}

Release() {
    global busy, lastActionTime, cfg, safeModeLines

    if (cfg.safeMode && safeModeLines.Length() > 0) {
        block := ""
        for i, line in safeModeLines
            block .= line . ((i < safeModeLines.MaxIndex()) ? "`n" : "")
        Clipboard := block
        count := safeModeLines.MaxIndex()
        TrayTip, МВД Helper, SafeMode: %count% строк в буфере.`nВставьте в чат (Ctrl+V) и отправьте построчно., 4, 1
        LogWrite("Release SafeMode: " . count . " lines to clipboard")
    }

    safeModeLines := []
    lastActionTime := A_TickCount
    busy := false
}

; ==============================================================================
; CORE: SendChat / SendKey / SendText / Seq
; ==============================================================================
SendChat(text, pressEnter:=true) {
    global cfg, safeModeLines

    if (!IsGameActive()) {
        DiagTip("SendChat: игра не в фокусе, пропуск")
        return false
    }

    if (cfg.safeMode) {
        safeModeLines.Push(text)
        LogWrite("SendChat SafeMode: buffered <- " . SubStr(text, 1, 40))
        return true
    }

    ; Отпускаем только Alt
    if (cfg.releaseAltOnly) {
        SendKey_Raw("{LAlt Up}{RAlt Up}")
    }

    ; Опциональный сброс Shift/Ctrl для чата
    if (cfg.forceChatKeyNoMods) {
        sh := GetKeyState("Shift")
        ct := GetKeyState("Ctrl")
        if (sh)
            SendKey_Raw("{Shift Up}")
        if (ct)
            SendKey_Raw("{Ctrl Up}")

        SendKey_Raw("{" . cfg.chatKey . "}")

        ; Восстанавливаем ТОЛЬКО если клавиша всё ещё физически нажата
        if (ct && GetKeyState("Ctrl", "P"))
            SendKey_Raw("{Ctrl Down}")
        if (sh && GetKeyState("Shift", "P"))
            SendKey_Raw("{Shift Down}")
    } else {
        SendKey_Raw("{" . cfg.chatKey . "}")
    }

    Sleep, % cfg.chatOpenDelay

    SendText(text)

    if (pressEnter) {
        Sleep, % cfg.afterTypeDelay
        SendKey_Raw("{Enter}")
    }

    return true
}

SendKey_Raw(keys) {
    global cfg
    if (cfg.sendMethod = "Event")
        SendEvent, %keys%
    else
        SendInput, %keys%
}

SendText(txt) {
    global cfg
    if (cfg.sendMethod = "Event")
        SendEvent, {Text}%txt%
    else
        SendInput, {Text}%txt%
}

Seq(lines, minMs:="", maxMs:="") {
    global cfg, safeModeLines
    if (minMs == "")
        minMs := cfg.seqMin
    if (maxMs == "")
        maxMs := cfg.seqMax

    if (cfg.safeMode) {
        for i, line in lines
            safeModeLines.Push(line)
        LogWrite("Seq SafeMode: " . lines.MaxIndex() . " lines buffered")
        return true
    }

    for i, line in lines {
        if (!IsGameActive()) {
            TrayTip, МВД Helper, Прервано: игра не в фокусе!, 2, 2
            LogWrite("Seq ABORTED at line " . i . ": game inactive")
            return false
        }
        if (!SendChat(line)) {
            LogWrite("Seq ABORTED at line " . i . ": SendChat failed")
            return false
        }
        if (i < lines.MaxIndex()) {
            Random, pause, %minMs%, %maxMs%
            Sleep, %pause%
        }
    }
    return true
}

; ==============================================================================
; CORE: Диалоги ввода
; ==============================================================================
Ask(prompt, def:="") {
    InputBox, out, МВД Helper, %prompt%, , 320, 150, , , , , %def%
    return {ok: !ErrorLevel, val: out}
}

AskReq(prompt, def:="") {
    res := Ask(prompt, def)
    if (!res.ok)
        return ""
    val := Trim(res.val)
    return (val == "") ? "" : val
}

AskDigits(prompt, def:="") {
    res := Ask(prompt, def)
    if (!res.ok)
        return ""
    val := Trim(res.val)
    if (val == "")
        return ""
    if RegExMatch(val, "^\d+$")
        return val
    MsgBox, 48, Ошибка, Введите только цифры.
    return ""
}

AskInt(prompt, def:="", minVal:=0, maxVal:=2147483647) {
    val := AskDigits(prompt, def)
    if (val == "")
        return ""
    n := val + 0
    if (n < minVal || n > maxVal) {
        MsgBox, 48, Ошибка, Значение: %minVal% – %maxVal%.
        return ""
    }
    return n
}

; ==============================================================================
; IsGameActive (с кэшем)
; ==============================================================================
IsGameActive() {
    global gameExes, gameActiveCache, gameActiveCacheTime, CACHE_TTL
    if (A_TickCount - gameActiveCacheTime < CACHE_TTL)
        return gameActiveCache
    gameActiveCacheTime := A_TickCount
    for _, ex in gameExes {
        if WinActive("ahk_exe " . ex) {
            gameActiveCache := true
            return true
        }
    }
    gameActiveCache := false
    return false
}

; ==============================================================================
; ПОГОНЫ (Rivera): описание по званию
; ==============================================================================
GetPogonLine(rank) {
    static pogonMap := ""
    if (!IsObject(pogonMap)) {
        pogonMap := {}
        pogonMap["Рядовой"]             := "На плечах закреплены пустые погоны."
        pogonMap["Сержант"]             := "На плечах закреплены погоны с тремя лычками поперек погон."
        pogonMap["Старшина"]            := "На плечах погоны с одной лычкой вдоль погон."
        pogonMap["Прапорщик"]           := "На плечах погоны с двумя звездами вдоль погон."
        pogonMap["Лейтенант"]           := "На плечах погоны с двумя звездами и просветом."
        pogonMap["Старший лейтенант"]   := "На плечах погоны с тремя звездами и просветом."
        pogonMap["Капитан"]             := "На плечах погоны с четырьмя звездами и просветом."
        pogonMap["Майор"]               := "На плечах погоны с одной звездой и двумя просветами."
        pogonMap["Подполковник"]         := "На плечах погоны с двумя звездами и двумя просветами."
        pogonMap["Полковник"]           := "На плечах погоны с тремя звездами и двумя просветами."
        pogonMap["Генерал-майор"]       := "На плечах погоны с одной большой звездой."
        pogonMap["Генерал-лейтенант"]   := "На плечах погоны с двумя большими звездами."
        pogonMap["Генерал-полковник"]   := "На плечах погоны с тремя большими звездами."
        pogonMap["Генерал МВД"]         := "На плечах погоны с одной большой звездой и гербом МВД."
    }
    return pogonMap.HasKey(rank) ? pogonMap[rank] : ""
}

; ==============================================================================
; ГЕНДЕРНЫЕ ОКОНЧАНИЯ (Rivera)
; ==============================================================================
ApplyGenderSuffixes(gender) {
    global gOk1, gOk2, gOk3
    if (gender == "Ж") {
        gOk1 := "а"    ; достал→достала
        gOk2 := "ла"   ; поднёс→поднесла
        gOk3 := "ась"  ; связался→связалась
    } else {
        gOk1 := ""
        gOk2 := ""
        gOk3 := "ся"
    }
}

; ==============================================================================
; INI: Создание / Чтение конфига / Профили
; ==============================================================================
EnsureIniExists() {
    global iniFile
    if !FileExist(iniFile) {
        FileAppend, % "[Main]`nActiveProfile=`n`n[Config]`n", %iniFile%, UTF-16
        LogWrite("INI created: " . iniFile)
        return
    }
    IniRead, s, %iniFile%
    if (s == "ERROR")
        return
    hasMain := false, hasConfig := false
    Loop, Parse, s, `n, `r
    {
        sec := Trim(A_LoopField)
        if (sec == "Main")
            hasMain := true
        if (sec == "Config")
            hasConfig := true
    }
    if (!hasMain)
        IniWrite, %A_Space%, %iniFile%, Main, ActiveProfile
    if (!hasConfig) {
        IniWrite, 0, %iniFile%, Config, _init
        IniDelete, %iniFile%, Config, _init
    }
}

LoadConfig() {
    global cfg, iniFile

    cfg.chatKey          := ReadIniStr("Config", "ChatKey",          cfg.chatKey)
    cfg.cdMs             := ClampInt(ReadIniInt("Config", "CdMs",             cfg.cdMs), 500, 10000)
    cfg.chatOpenDelay    := ClampInt(ReadIniInt("Config", "ChatOpenDelay",    cfg.chatOpenDelay), 50, 2000)
    cfg.afterTypeDelay   := ClampInt(ReadIniInt("Config", "AfterTypeDelay",   cfg.afterTypeDelay), 20, 1000)
    cfg.seqMin           := ClampInt(ReadIniInt("Config", "SeqMin",           cfg.seqMin), 100, 5000)
    cfg.seqMax           := ClampInt(ReadIniInt("Config", "SeqMax",           cfg.seqMax), 100, 10000)
    cfg.releaseAltOnly   := ReadIniBool("Config", "ReleaseAltOnly",   cfg.releaseAltOnly)
    cfg.forceChatKeyNoMods := ReadIniBool("Config", "ForceChatKeyNoMods", cfg.forceChatKeyNoMods)

    v := ReadIniStr("Config", "SendMethod", cfg.sendMethod)
    cfg.sendMethod := (v = "Input") ? "Input" : "Event"

    cfg.safeMode         := ReadIniBool("Config", "SafeMode",        cfg.safeMode)
    cfg.gameExeList      := ReadIniStr("Config",  "GameExeList",     cfg.gameExeList)
    cfg.enableLog        := ReadIniBool("Config", "EnableLog",       cfg.enableLog)

    if (cfg.seqMax < cfg.seqMin)
        cfg.seqMax := cfg.seqMin + 100

    if (Trim(cfg.chatKey) == "") {
        cfg.chatKey := "t"
        LogWrite("WARN: ChatKey was empty in INI, reset to 't'")
    }

    if (Trim(cfg.gameExeList) == "") {
        cfg.gameExeList := "gta_sa.exe|Multi Theft Auto.exe"
        LogWrite("WARN: GameExeList was empty in INI, reset to default")
    }
}

; --- INI helpers ---
ReadIniStr(section, key, def:="") {
    global iniFile
    IniRead, v, %iniFile%, %section%, %key%, %def%
    return Trim(v)
}

ReadIniInt(section, key, def:=0) {
    v := ReadIniStr(section, key, def)
    return (v + 0)
}

ReadIniBool(section, key, def:=0) {
    return ReadIniInt(section, key, def) ? 1 : 0
}

ClampInt(val, lo, hi) {
    if (val < lo) return lo
    if (val > hi) return hi
    return val
}

ParseGameExeList() {
    global cfg, gameExes
    gameExes := []
    Loop, Parse, cfg.gameExeList, |
    {
        ex := Trim(A_LoopField)
        if (ex != "")
            gameExes.Push(ex)
    }
    if (gameExes.Length() == 0)
        gameExes.Push("gta_sa.exe")
}

; ==============================================================================
; SECTION CACHE
; ==============================================================================
UpdateSectionCache() {
    global iniFile, sectionSet
    sectionSet := {}
    if (!FileExist(iniFile)) {
        EnsureIniExists()
    }
    IniRead, sections, %iniFile%
    if (sections == "ERROR" || sections == "") {
        sectionSet["Main"] := true
        sectionSet["Config"] := true
        return
    }
    Loop, Parse, sections, `n, `r
    {
        s := Trim(A_LoopField)
        if (s != "")
            sectionSet[s] := true
    }
}

SectionExists(name) {
    global sectionSet
    return IsObject(sectionSet) && sectionSet.HasKey(name)
}

IsReservedSection(name) {
    return (name = "Main" || name = "Config")
}

; ==============================================================================
; ПРОФИЛИ (расширенные: +Greeting, +Gender)
; ==============================================================================
SanitizeProfileName(name) {
    name := Trim(name)
    if (name == "")
        return ""
    if RegExMatch(name, "[\[\]=;\r\n#]")
        return ""
    name := Trim(name)
    if (StrLen(name) > 50)
        return ""
    return name
}

ReadProfile(name) {
    global iniFile
    IniRead, gr, %iniFile%, %name%, Greeting, %A_Space%
    IniRead, st, %iniFile%, %name%, Structure, %A_Space%
    IniRead, rk, %iniFile%, %name%, Rank, %A_Space%
    IniRead, sn, %iniFile%, %name%, Surname, %A_Space%
    IniRead, ps, %iniFile%, %name%, Post, %A_Space%
    IniRead, dp, %iniFile%, %name%, DeptLine, %A_Space%
    IniRead, gd, %iniFile%, %name%, Gender, %A_Space%

    gr := (Trim(gr) == "") ? "Здравия желаю"  : Trim(gr)
    st := (Trim(st) == "") ? "УВД"            : Trim(st)
    rk := (Trim(rk) == "") ? "Сержант"        : Trim(rk)
    sn := (Trim(sn) == "") ? "Иванов"         : Trim(sn)
    ps := (Trim(ps) == "") ? "сотрудник"       : Trim(ps)
    dp := (Trim(dp) == "") ? "г. Невский"      : Trim(dp)
    gd := (Trim(gd) == "") ? "М"              : Trim(gd)

    return {Name: name, Greeting: gr, Structure: st, Rank: rk, Surname: sn, Post: ps, DeptLine: dp, Gender: gd}
}

WriteProfile(name, gr, st, rk, sn, ps, dp, gd) {
    global iniFile
    IniWrite, %gr%, %iniFile%, %name%, Greeting
    IniWrite, %st%, %iniFile%, %name%, Structure
    IniWrite, %rk%, %iniFile%, %name%, Rank
    IniWrite, %sn%, %iniFile%, %name%, Surname
    IniWrite, %ps%, %iniFile%, %name%, Post
    IniWrite, %dp%, %iniFile%, %name%, DeptLine
    IniWrite, %gd%, %iniFile%, %name%, Gender
}

LoadActiveProfile() {
    global currentProfile, iniFile
    IniRead, name, %iniFile%, Main, ActiveProfile, %A_Space%
    name := Trim(name)
    if (name == "") {
        currentProfile := {}
        return
    }
    currentProfile := ReadProfile(name)
    ApplyGenderSuffixes(currentProfile.Gender)
}

; ==============================================================================
; GUI HELPERS
; ==============================================================================
RefreshList() {
    global sectionSet, iniFile
    UpdateSectionCache()

    Gui, ListView, ProfileList
    LV_Delete()

    IniRead, activeName, %iniFile%, Main, ActiveProfile, %A_Space%
    activeName := Trim(activeName)

    names := ""
    for s, _ in sectionSet {
        if (s == "Main" || s == "Config")
            continue
        names .= s . "`n"
    }
    Sort, names

    selectRow := 0
    Loop, Parse, names, `n, `r
    {
        s := A_LoopField
        if (s == "")
            continue
        display := (s == activeName) ? ("★ " . s) : s
        row := LV_Add("", display)
        if (s == activeName)
            selectRow := row
    }
    if (selectRow > 0)
        LV_Modify(selectRow, "Select Focus")
}

StripActiveMarker(name) {
    if (SubStr(name, 1, 2) == "★ ")
        return SubStr(name, 3)
    if (SubStr(name, 1, 1) == "★")
        return Trim(SubStr(name, 2))
    return name
}

FillForm(p, name) {
    GuiControl,, EditName, %name%
    GuiControl, ChooseString, EditGreeting, % p.Greeting
    GuiControl, ChooseString, EditStruct, % p.Structure
    GuiControl, ChooseString, EditRank, % p.Rank
    GuiControl,, EditSurname, % p.Surname
    GuiControl,, EditPost, % p.Post
    GuiControl,, EditDept, % p.DeptLine
    GuiControl, ChooseString, EditGender, % p.Gender
}

ClearForm() {
    GuiControl,, EditName,
    GuiControl, Choose, EditGreeting, 1
    GuiControl, Choose, EditStruct, 1
    GuiControl, Choose, EditRank, 1
    GuiControl,, EditSurname,
    GuiControl,, EditPost,
    GuiControl,, EditDept,
    GuiControl, Choose, EditGender, 1
}

; ==============================================================================
; ЛОГИРОВАНИЕ
; ==============================================================================
LogWrite(msg) {
    global cfg
    if (!cfg.enableLog)
        return
    FormatTime, ts,, yyyy-MM-dd HH:mm:ss
    line := ts . " | " . msg . "`n"
    FileAppend, %line%, log.txt
}

DiagTip(msg) {
    global cfg
    LogWrite("DIAG: " . msg)
    if (cfg.enableLog)
        TrayTip, МВД Helper, %msg%, 1, 1
}
