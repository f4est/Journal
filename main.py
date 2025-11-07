import sys, os, sqlite3
from typing import Optional, List

from PyQt5.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QPushButton, QLineEdit, QComboBox, QTableWidget,
    QTableWidgetItem, QMessageBox, QAbstractItemView,
    QFrame, QSplitter, QPlainTextEdit, QFileDialog, QHeaderView,
    QMenu, QDialog, QDialogButtonBox, QCalendarWidget, QCheckBox,
    QToolButton, QGroupBox, QInputDialog, QTextEdit, QSlider, QColorDialog, QStyleFactory
)
from PyQt5.QtGui import QIcon, QColor, QFont, QPixmap, QPainter
from PyQt5.QtCore import Qt, QSize

# ------------ ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И ДАННЫЕ ---------------

def get_parallel_group_name(group_name: str) -> Optional[str]:
    """
    Если передана теоретическая группа, вернуть её лаб-пару.
    Если передана лаб-группа, вернуть базовую теоретическую.
    Если пара не выводится из названия – вернуть None
    """
    if group_name.endswith("_Лаб"):
        return group_name[:-4]          # срезаем суффикс
    else:
        return f"{group_name}_Лаб"

def resource_path(relative_path):
    return os.path.join(os.path.abspath("."), relative_path)

def get_config_path():
    return os.path.join(os.getenv("APPDATA"), ".journal_app", "config.json")

def get_db_path():
    app_dir = os.path.join(os.getenv("APPDATA"), ".journal_app", "noupdated")
    if not os.path.exists(app_dir):
        os.makedirs(app_dir, exist_ok=True)
    return os.path.join(app_dir, "journal_data.db")

def get_image_path(image_name):
    app_dir = os.path.join(os.getenv("APPDATA"), ".journal_app", "updated")
    images_dir = os.path.join(app_dir, "images")
    if not os.path.exists(images_dir):
        os.makedirs(images_dir, exist_ok=True)
    return os.path.join(images_dir, image_name)

DB_NAME = get_db_path()

# Заголовки специальных полей
class_names_rus = {
    "letter_count": "Н",
    "ro_value":     "РО",
    "otrabotka":    "Отработка",
    "r_value":      "Р",
    "exam":         "Экзам",
    "itog_value":   "Итог",
    "digital_equivalent": "Циф. экв.",
    "letter_equivalent":  "Бук. экв."
}

def get_grade_color(grade_str):
    """Пример функции динамической раскраски числовых значений от 0 до 100."""
    app = QApplication.instance()
    if app and app.property("disable_colors"):
        return None
    try:
        grade = float(grade_str)
    except:
        return None
    if grade < 50:
        return QColor(255, 102, 102)   # ярко-красный
    elif grade < 70:
        return QColor(255, 178, 102)   # оранжевый
    elif grade < 90:
        return QColor(255, 255, 153)   # жёлтый
    else:
        return QColor(153, 255, 153)   # светло-зелёный
    
def tint_icon(pixmap, color):
    """Возвращает QIcon, полученный перекрашиванием исходного pixmap в заданный color."""
    tinted = QPixmap(pixmap.size())
    tinted.fill(Qt.transparent)
    
    painter = QPainter(tinted)
    # Сначала рисуем исходное изображение
    painter.setCompositionMode(QPainter.CompositionMode_Source)
    painter.drawPixmap(0, 0, pixmap)
    # Затем, используя режим SourceIn, «перекрашиваем» изображение
    painter.setCompositionMode(QPainter.CompositionMode_SourceIn)
    painter.fillRect(tinted.rect(), color)
    painter.end()
    
    return QIcon(tinted)

def get_equivalents(final_score):
    """Возвращает (буквенная_оценка, цифровой_эквивалент) для final_score."""
    if final_score >= 95:
        return "A", "4.00"
    elif final_score >= 90:
        return "A-", "3.67"
    elif final_score >= 85:
        return "B+", "3.33"
    elif final_score >= 80:
        return "B", "3.00"
    elif final_score >= 75:
        return "B-", "2.67"
    elif final_score >= 70:
        return "C+", "2.33"
    elif final_score >= 65:
        return "C", "2.00"
    elif final_score >= 60:
        return "C-", "1.67"
    elif final_score >= 55:
        return "D+", "1.33"
    elif final_score >= 50:
        return "D", "1.00"
    else:
        return "F", "0.00"
    
# ─── Сброс отработки, когда Н = 0 ──────────────────────────────────────────
def reset_otrabotka_if_needed(cur: sqlite3.Cursor, student_id: int,
                              n_count: int, otrabotka_val: float):
    """
    Если Н == 0 и отработка всё ещё > 0 — сбрасываем её на 0.
    Возвращает (новое_значение_отрabotka).
    """
    if n_count == 0 and otrabotka_val:
        cur.execute("UPDATE students SET otrabotka=0 WHERE id=?", (student_id,))
        return 0.0
    return otrabotka_val

def calc_classic_values(
    numeric_sum: float,
    count_numeric: int,
    count_n: int,
    otrabotka: float,
    exam: float,
    include_exam: bool,
    lab_data=None
):
    """
    Теория:
      RO = (sum теории + sum лабок) / (кол-во дат теории + кол-во дат лабок)
      O  = otrabotka (пользователь ввёл)
      R  = (sum теории + sum лабок + sum lab_otrabotka + otrabotka) /
           ((кол-во дат теории - count_n + (1 если otrabotka>0)) + кол-во дат лабок)
      Итог = R*0.6 + exam*0.4  (если include_exam)
    """
    # Данные из лабок
    lab_sum = lab_data.get('sum', 0.0) if lab_data else 0.0
    lab_count = lab_data.get('count', 0) if lab_data else 0
    lab_o_sum = lab_data.get('otrabotka_sum', 0.0) if lab_data else 0.0
    lab_o_cnt = lab_data.get('otrabotka_count', 0) if lab_data else 0

    # RO
    dates_theory = count_numeric + count_n
    total_dates = dates_theory + lab_count
    ro_val = (numeric_sum + lab_sum) / total_dates if total_dates else 0.0

    # O
    o_val = otrabotka if otrabotka > 0 else 0.0

    # R
    # считается: (sum чисел + sum лаб.чисел + sum лаб.отр + otrabotka) /
    #           ((dates_theory - count_n + (1 если otrabotka>0)) + lab_count)
    eff_theory = (dates_theory - count_n) + (1 if otrabotka > 0 else 0)
    denom = eff_theory + lab_count
    numerator = numeric_sum + lab_sum + lab_o_sum + o_val
    r_val = numerator / denom if denom else 0.0

    # Итог
    if include_exam:
        it_val = r_val * 0.6 + exam * 0.4
    else:
        it_val = r_val

    let, dig = get_equivalents(it_val)
    return ro_val, r_val, it_val, let, dig

# ───────────────────────────────
#  ВСПОМОГАТЕЛЬНАЯ ФУНКЦИЯ
# ───────────────────────────────
def get_grades_array(cur: sqlite3.Cursor,
                     group_id: int,
                     student_id: int) -> List[str]:
    """
    Возвращает список строк длиной **кол-во дат в группе**.
    Для каждой даты:
        ""   – если оценки нет,
        "Н"  – если стоит Н,
        "xx" – любая оценка/число.
    Позиции строго соответствуют ORDER BY date_id.
    """
    # все даты (их id) данной группы
    cur.execute("SELECT id FROM dates WHERE group_id=? ORDER BY id", (group_id,))
    date_ids = [r[0] for r in cur.fetchall()]

    # все оценки студента   {date_id: grade}
    cur.execute(
        "SELECT date_id, COALESCE(grade,'') FROM grades "
        "WHERE student_id=?", (student_id,))
    gr_dict = {row[0]: row[1] for row in cur.fetchall()}

    # финальный массив
    return [gr_dict.get(did, "") for did in date_ids]

def calc_labprakt_values(grades_list: list, manual_o: float, lab_dates_count: int):
    """
    Лабораторная группа:
      RO = сумма числовых оценок / lab_dates_count
      O  = manual_o  (т.к. у вас одно поле отработки)
      R  = (сумма оценок + manual_o) / (lab_dates_count + (1 если manual_o>0))
    Итог = R
    """
    # Собираем только цифровые оценки
    nums = []
    for g in grades_list:
        try:
            v = float(g)
            nums.append(min(v, 100))
        except:
            continue

    sum_nums = sum(nums)
    cnt_nums = len(nums)

    # RO
    ro_val = sum_nums / lab_dates_count if lab_dates_count else 0.0

    # O  
    o_val = manual_o if manual_o > 0 else 0.0
    cnt_o = 1 if manual_o > 0 else 0

    # R
    denom = lab_dates_count + cnt_o
    r_val = (sum_nums + o_val) / denom if denom else 0.0

    it_val = r_val
    let, dig = get_equivalents(it_val)

    # letter_count = сколько Н, но в лабках мы не считаем "Н" – оставим 0
    return ro_val, r_val, it_val, let, dig, 0

def calc_lab_values(grades_list: list, manual_o: float):
    """
    Лабораторная группа:

      Н  = cколько 'Н'
      РО = сумма числовых оценок / **общее количество дат**
      О  = manual_o
      Р  = (сумма(числа) + manual_o * Н) /
           (кол-во дат + (1, если manual_o > 0))
    """
    count_n = 0
    numeric_vals = []
    for g in grades_list:
        val = str(g).strip().upper()
        if val == '':
            numeric_vals.append(0.0)
            continue
        if g == 'Н':
            count_n += 1
            continue
        try:
            numeric_vals.append(float(val))
        except ValueError:
            count_n += 1         

    total_dates = len(grades_list)                 # ← все даты!
    ro_val = sum(numeric_vals) / total_dates if total_dates else 0.0

    r_sum  = sum(numeric_vals) + manual_o * count_n
    denom  = total_dates 
    r_val  = r_sum / denom if denom else 0.0

    return count_n, ro_val, manual_o, r_val

def calc_theory_lab_values(theory_grades: list,
                           manual_o: float,
                           exam: float,
                           include_exam: bool,
                           lab_data: dict):
    """
    Расчёт показателей для ТЕОРИИ (может быть включена «подтяжка» из лабок).

    • Пустая ячейка = 0 (не «Н»)  
    • 'Н' увеличивает count_n, но не влияет на O/denom напрямую  
    • В числитель R добавляется ОДИН manual_o, а не O*count_n  
    • В знаменатель R прибавляется +1, только если manual_o > 0
    """
    # ---------- теория ---------------------------------------------------
    numeric_sum = 0.0      # сумма числовых оценок
    cnt_dates   = len(theory_grades)
    count_n     = 0

    for g in theory_grades:
        g = str(g).strip()
        if not g:                     # пусто → 0
            continue
        if g.upper() == 'Н':
            count_n += 1              # Н
            continue
        try:
            numeric_sum += float(g)
        except ValueError:            # «странное» значение → Н
            count_n += 1

    # ---------- лабораторные данные -------------------------------------
    lab_cnt          = lab_data.get('lab_count', 0)
    lab_numeric_sum  = lab_data.get('lab_numeric_sum', 0.0)
    lab_replaced_sum = lab_data.get('lab_replaced_sum', 0.0)

    # ---------- RO -------------------------------------------------------
    total_dates = cnt_dates + lab_cnt
    ro_val = (numeric_sum + lab_numeric_sum) / total_dates if total_dates else 0.0

    # ---------- R --------------------------------------------------------
    numerator = numeric_sum + lab_replaced_sum + manual_o
    denom = (cnt_dates - count_n) + lab_cnt + (1 if manual_o > 0 else 0)
    r_val = numerator / denom if denom else 0.0

    # ---------- Итог и эквиваленты --------------------------------------
    it_val = 0.6 * r_val + 0.4 * exam if include_exam else r_val
    let, dig = get_equivalents(it_val)

    return count_n, ro_val, manual_o, r_val, exam, it_val, let, dig

# ------------- DIALOG: RupyWindow для примера ---------------
class RupyWindow(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Rupy")
        self.resize(400,300)
        layout = QVBoxLayout(self)
        lbl = QLabel("Это окно Rupy. Функционал пока не реализован.")
        layout.addWidget(lbl)
        btn = QPushButton("Закрыть")
        btn.clicked.connect(self.close)
        layout.addWidget(btn)


# ------------- DIALOG: DocumentationDialog ---------------
class DocumentationDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Документация по Электронному Журналу")
        self.resize(700,550)
        layout = QVBoxLayout(self)
        self.doc_text = QTextEdit()
        self.doc_text.setReadOnly(True)
        layout.addWidget(self.doc_text)
        btn_box = QDialogButtonBox(QDialogButtonBox.Close)
        btn_box.rejected.connect(self.reject)
        btn_box.accepted.connect(self.accept)
        layout.addWidget(btn_box)
        self.populate_documentation()
    
    def populate_documentation(self):
        doc = (
            "ЭЛЕКТРОННЫЙ ЖУРНАЛ – ПОДРОБНАЯ ДОКУМЕНТАЦИЯ\n"
            "=============================================\n\n"
            "1. НАВИГАЦИОННОЕ МЕНЮ\n"
            "---------------------\n"
            "• Файл:\n"
            "  - Импорт – загрузка данных из Excel-файла.\n"
            "  - Экспорт – сохранение данных в Excel.\n"
            "  - Резервная копия – сохранение резервной копии.\n"
            "  - Восстановить – восстановление данных.\n\n"
            "• Группа:\n"
            "  - Добавить группу – создание новой группы.\n"
            "  - Удалить группу – удаление выбранной группы.\n\n"
            "• Студенты/Даты:\n"
            "  - Студенты – добавление студентов.\n"
            "  - Даты – добавление дат.\n\n"
            "• Рассчитать:\n"
            "  - Рассчитать – перерасчёт оценок.\n\n"
            "• Rupy:\n"
            "  - Нажмите Rupy для открытия отдельного окна.\n\n"
            "• Поиск:\n"
            "  - Локальный поиск.\n"
            "  - Глобальный поиск.\n\n"
            "2. НАСТРОЙКИ\n"
            "-----------\n"
            "Вы можете менять тему, цвета, масштаб и т.д.\n\n"
            "3. РЕЗЕРВНОЕ КОПИРОВАНИЕ\n"
            "------------------------\n"
            "Используйте кнопки Резервная копия и Восстановить.\n\n"
        )
        self.doc_text.setPlainText(doc)


# ------------- DIALOG: SettingsDialog c цветами ---------------
from PyQt5.QtWidgets import QScrollArea  # убедитесь, что импортируете QScrollArea

class SettingsDialog(QDialog):
    def __init__(self, current_scale=100, show_log=False, disable_colors=False,
                 colors=None, parent=None):
        super().__init__(parent)
        
        self.setWindowTitle("Настройки")
        self.resize(600, 500)

        default_colors = {
            "main_window_bg": QColor("#ffffff"),  # Фон приложения
            "table_bg": QColor("#ffffff"),         # Фон таблицы
            "btn_bg": QColor("#1e3c72"),           # Кнопки (синий)
            "n_cell_bg": QColor("#f0f0f0"),          # Цвет для "Н"
            "otrabotka_bg": QColor("#c8dcff"),       # Цвет для отработки
            "date_color": QColor("#7e9bb7"),         # Цвет дат (светло-голубой)
            "student_color": QColor("#ffffff"),      # Цвет студентов (светло-зелёный)
            "popup_bg": QColor("#ffffff"),           # Цвет всплывающих окон
            "icon_color": QColor("#1e3c72")          # Цвет иконок
        }
        
        self._current_scale = current_scale
        self._show_log = show_log
        self._disable_colors = disable_colors
        self.colors = colors  or default_colors.copy()
        
        self.btn_map = {}
        
        # Основной вертикальный layout диалога
        main_layout = QVBoxLayout(self)
        main_layout.setContentsMargins(20, 20, 20, 20)
        main_layout.setSpacing(15)

         # --- Верхний горизонтальный layout для кнопки обновления ---
        header_button_layout = QHBoxLayout()
        header_button_layout.addStretch()  # Растягивает пространство слева
        btn_update = QPushButton()
        btn_update.setIcon(QIcon(get_image_path("update.png")))  # Замените на реальный путь к иконке обновления
        btn_update.setToolTip("Проверить обновления")
        btn_update.clicked.connect(self.check_for_updates)
        header_button_layout.addWidget(btn_update)
        main_layout.addLayout(header_button_layout)
        
        # Заголовок
        lbl_title = QLabel("Настройки приложения")
        lbl_title.setAlignment(Qt.AlignCenter)
        font_title = lbl_title.font()
        font_title.setPointSize(16)
        font_title.setBold(True)
        lbl_title.setFont(font_title)
        main_layout.addWidget(lbl_title)
        
        # Создаем контейнер для основного содержимого
        content_widget = QWidget()
        content_layout = QVBoxLayout(content_widget)
        content_layout.setSpacing(15)
        
        # --- Группа: Основные ---
        group_general = QGroupBox("Основные")
        group_general_layout = QVBoxLayout(group_general)
        
        lbl_scale = QLabel("Масштаб интерфейса (100–200%):")
        self.scale_slider = QSlider(Qt.Horizontal)
        self.scale_slider.setRange(100, 200)
        self.scale_slider.setValue(self._current_scale)
        self.scale_value_label = QLabel(f"{self._current_scale}%")
        self.scale_slider.valueChanged.connect(lambda val: self.scale_value_label.setText(f"{val}%"))
        
        hl_scale = QHBoxLayout()
        hl_scale.addWidget(self.scale_slider)
        hl_scale.addWidget(self.scale_value_label)
        group_general_layout.addWidget(lbl_scale)
        group_general_layout.addLayout(hl_scale)
        
        self.chk_log = QCheckBox("Показывать журнал действий")
        self.chk_log.setChecked(self._show_log)
        group_general_layout.addWidget(self.chk_log)
        
        self.chk_disable_colors = QCheckBox("Отключить всю цветовую раскраску")
        self.chk_disable_colors.setChecked(self._disable_colors)
        group_general_layout.addWidget(self.chk_disable_colors)
        
        content_layout.addWidget(group_general)
        
        # --- Группа: Цвета ---
        group_colors = QGroupBox("Цвета")
        group_colors_layout = QVBoxLayout(group_colors)
        
        def create_color_button(text, key):
            btn = QPushButton(text)
            self.btn_map[key] = btn
            self.update_button_color_preview(btn, self.colors[key])
            btn.clicked.connect(lambda: self.pick_color(key))
            group_colors_layout.addWidget(btn)
            return btn
        
        create_color_button("Фон приложения", "main_window_bg")
        create_color_button("Фон таблицы", "table_bg")
        create_color_button("Кнопки", "btn_bg")
        create_color_button("Цвет Н", "n_cell_bg")
        create_color_button("Цвет отработки", "otrabotka_bg")
        create_color_button("Цвет дат", "date_color")
        create_color_button("Цвет студентов", "student_color")
        create_color_button("Цвет всплывающих окон", "popup_bg")    
        create_color_button("Цвет иконок", "icon_color")   
        self.btn_change_icon_color = QPushButton("Изменить цвет иконок")
        self.update_button_color_preview(self.btn_change_icon_color, self.colors["icon_color"])
        self.btn_change_icon_color.clicked.connect(self.change_icon_color)
        group_colors_layout.addWidget(self.btn_change_icon_color)
        
        btn_default = QPushButton("Цвет по умолчанию")
        btn_default.clicked.connect(self.reset_default_colors)
        group_colors_layout.addWidget(btn_default)
        
        content_layout.addWidget(group_colors)
        
        # --- Документация ---
        btn_help = QPushButton("Открыть документацию")
        btn_help.clicked.connect(self.open_documentation)
        hl_help = QHBoxLayout()
        hl_help.addStretch()
        hl_help.addWidget(btn_help)
        content_layout.addLayout(hl_help)
        
        # Помещаем содержимое в QScrollArea
        scroll_area = QScrollArea()
        scroll_area.setWidgetResizable(True)
        scroll_area.setWidget(content_widget)
        main_layout.addWidget(scroll_area)
        
        # --- Кнопки ОК/Отмена ---
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        btn_box.accepted.connect(self.accept)
        btn_box.rejected.connect(self.reject)
        main_layout.addWidget(btn_box)
    
    def check_for_updates(self):
        # Определяем пути и URL для проверки обновлений
        APP_DATA_PATH = os.path.join(os.getenv("APPDATA"), ".journal_app")
        LOCAL_VERSION_FILE = os.path.join(APP_DATA_PATH,"updated", "version.txt")
        #REMOTE_VERSION_URL = "https://raw.githubusercontent.com/f4est/Journal-app/refs/heads/main/app/updated/version.txt"  # Замените на актуальный URL
        REMOTE_VERSION_URL = "https://raw.githubusercontent.com/f4est/Journal-app/main/app/updated/version.txt"

        def get_local_version():
            # Если файла нет, создаём его и записываем версию "1.0.0"
            if not os.path.exists(LOCAL_VERSION_FILE):
                with open(LOCAL_VERSION_FILE, "w") as f:
                    f.write("1.0.0")
                return "1.0.0"
            with open(LOCAL_VERSION_FILE, "r") as f:
                return f.read().strip()

        def get_remote_version():
            GITHUB_ACCESS_TOKEN = "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"

            headers = {
                "Authorization": f"token {GITHUB_ACCESS_TOKEN}",
                "Accept": "application/vnd.github.v3.raw"  # можно указать для получения сырого содержимого
            }
            try:
                import requests
                response = requests.get(REMOTE_VERSION_URL, headers=headers, timeout=10)
                print(response)
                if response.status_code == 200:
                    return response.text.strip()
            except Exception as e:
                print("Ошибка при получении удалённой версии:", e)
            return None

        def check_for_update_inner():
            print(get_local_version())
            print(get_remote_version())
            local_ver = get_local_version().strip().rstrip('.')
            remote_ver = get_remote_version().strip().rstrip('.')
            if remote_ver:
                print("Локальная версия:", local_ver)
                print("Удалённая версия:", remote_ver)
                from packaging import version
                if version.parse(remote_ver) > version.parse(local_ver):
                    return True, remote_ver
            return False, local_ver

        def launch_updater():
            updater_exe = os.path.join(APP_DATA_PATH,"noupdated", "UpdaterJournal.exe")
            if os.path.exists(updater_exe):
                try:
                    import subprocess
                    subprocess.Popen([updater_exe])
                    print("Запущен процесс обновления.")
                    sys.exit(0)
                except Exception as e:
                    print("Не удалось запустить обновление:", e)
            else:
                print(f"Файл обновления не найден: {updater_exe}")

        need_update, ver = check_for_update_inner()
        if need_update:
            reply = QMessageBox.question(
                self,
                "Обновление",
                f"Доступно обновление (версия {ver}).\nХотите обновить приложение сейчас?",
                QMessageBox.Yes | QMessageBox.No,
                QMessageBox.Yes
            )
            if reply == QMessageBox.Yes:
                launch_updater()
            else:
                QMessageBox.information(self, "Обновление", "Обновление отменено пользователем.")
        else:
            QMessageBox.information(self, "Обновление", "Приложение актуально, обновление не требуется.")

    def pick_color(self, key):
        init_color = self.colors.get(key, QColor("white"))
        chosen = QColorDialog.getColor(init_color, self, "Выберите цвет")
        if chosen.isValid():
            self.colors[key] = chosen
            btn = self.btn_map.get(key)
            if (btn):
                self.update_button_color_preview(btn, chosen)
    
    def update_button_color_preview(self, button, color):
        pix = QPixmap(16, 16)
        pix.fill(color)
        button.setIcon(QIcon(pix))
    
    def reset_default_colors(self):
        default_colors = {
            "main_window_bg": QColor("#ffffff"),  # Фон приложения
            "table_bg": QColor("#ffffff"),         # Фон таблицы
            "btn_bg": QColor("#1e3c72"),           # Кнопки (синий)
            "n_cell_bg": QColor("#f0f0f0"),          # Цвет для "Н"
            "otrabotka_bg": QColor("#c8dcff"),       # Цвет для отработки
            "date_color": QColor("#7e9bb7"),         # Цвет дат (светло-голубой)
            "student_color": QColor("#ffffff"),      # Цвет студентов (светло-зелёный)
            "popup_bg": QColor("#ffffff"),           # Цвет всплывающих окон
            "icon_color": QColor("#1e3c72")          # Цвет иконок
        }
        self.colors = default_colors.copy()
        for key, btn in self.btn_map.items():
            self.update_button_color_preview(btn, self.colors[key])
        QMessageBox.information(self, "Сброс", "Цвета сброшены к значениям по умолчанию.")
    
    def change_icon_color(self):
        """Открывает QColorDialog для выбора нового цвета и сохраняет его в словаре colors."""
        current_color = self.colors.get("icon_color", QColor("#1e3c72"))
        chosen = QColorDialog.getColor(current_color, self, "Выберите цвет иконок")
        if chosen.isValid():
            self.colors["icon_color"] = chosen
            # Можно обновить иконку кнопки для примера:
            pix = QPixmap(16, 16)
            pix.fill(chosen)
            self.btn_change_icon_color.setIcon(QIcon(pix))
    
    def get_colors(self):
        return self.colors
    
    def get_scale_value(self):
        return self.scale_slider.value()
    
    def get_show_log_value(self):
        return self.chk_log.isChecked()
    
    def get_disable_colors_value(self):
        return self.chk_disable_colors.isChecked()
    
    def open_documentation(self):
        dlg = DocumentationDialog(self)
        dlg.exec_()



# ------------- DIALOG: GlobalSearchDialog ---------------
class GlobalSearchDialog(QDialog):
    def __init__(self, db_conn, query, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Глобальный поиск")
        self.resize(600,400)
        self.db_conn = db_conn
        self.query = query
        layout = QVBoxLayout(self)
        self.table = QTableWidget()
        layout.addWidget(self.table)
        self.populate_results()
        btn_box = QDialogButtonBox(QDialogButtonBox.Close)
        btn_box.rejected.connect(self.reject)
        layout.addWidget(btn_box)
    
    def populate_results(self):
        cursor = self.db_conn.cursor()
        cursor.execute(
            "SELECT g.group_name, s.student_name, s.itog_value "
            "FROM students s JOIN groups g ON s.group_id = g.id "
            "WHERE lower(s.student_name) LIKE ? "
            "ORDER BY g.group_name, s.student_name",
            (f"%{self.query}%",)
        )
        rows = cursor.fetchall()
        self.table.setColumnCount(3)
        self.table.setHorizontalHeaderLabels(["Группа", "Студент", "Итог"])
        self.table.setRowCount(len(rows))
        for r, row in enumerate(rows):
            for c, val in enumerate(row):
                item = QTableWidgetItem(str(val))
                item.setTextAlignment(Qt.AlignCenter)
                self.table.setItem(r, c, item)
        self.table.resizeColumnsToContents()


# ------------- CUSTOM WIDGET: UndoableTableWidget ---------------
class UndoableTableWidget(QTableWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._last_value = {}
    def editItem(self, item):
        self._last_value[(item.row(), item.column())] = item.text()
        super().editItem(item)
    def mousePressEvent(self, event):
        if event.button() == Qt.RightButton:
            event.ignore()
            self.customContextMenuRequested.emit(event.pos())
        else:
            super().mousePressEvent(event)

# ------------- MULTI SELECT CALENDAR ---------------
class MultiSelectCalendar(QCalendarWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setSelectionMode(QCalendarWidget.SingleSelection)
        self.setGridVisible(True)
        self.selected_dates = set()
        self.last_date = None
        self.clicked.connect(self.on_clicked)
    def on_clicked(self, qdate):
        mods = QApplication.keyboardModifiers()
        ctrl = bool(mods & Qt.ControlModifier)
        shift = bool(mods & Qt.ShiftModifier)
        if ctrl:
            if qdate in self.selected_dates:
                self.selected_dates.remove(qdate)
            else:
                self.selected_dates.add(qdate)
            self.last_date = qdate
        elif shift:
            if self.last_date is None:
                self.selected_dates.clear()
                self.selected_dates.add(qdate)
                self.last_date = qdate
            else:
                d1 = self.last_date
                d2 = qdate
                if d2 < d1:
                    d1, d2 = d2, d1
                dd = d1
                while dd <= d2:
                    self.selected_dates.add(dd)
                    dd = dd.addDays(1)
                self.last_date = qdate
        else:
            self.selected_dates.clear()
            self.selected_dates.add(qdate)
            self.last_date = qdate
        self.updateCells()
    def paintCell(self, painter, rect, date):
        super().paintCell(painter, rect, date)
        if date in self.selected_dates:
            painter.save()
            color = QColor(224,32,34,120)
            painter.setBrush(color)
            painter.setPen(Qt.NoPen)
            painter.drawRect(rect)
            painter.restore()

class MultiCalendarDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Выбор дат (Shift/Ctrl)")
        self.resize(400,400)
        lay = QVBoxLayout(self)
        self.cal = MultiSelectCalendar()
        lay.addWidget(self.cal)
        self.text_box = QPlainTextEdit()
        self.text_box.setReadOnly(True)
        self.text_box.setFixedHeight(80)
        lay.addWidget(self.text_box)
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok|QDialogButtonBox.Cancel)
        lay.addWidget(btn_box)
        btn_box.accepted.connect(self.accept)
        btn_box.rejected.connect(self.reject)
        self.cal.clicked.connect(self.on_cal_clicked)
    def on_cal_clicked(self):
        s_dates = sorted(self.cal.selected_dates)
        if not s_dates:
            self.text_box.setPlainText("(нет)")
        else:
            lines = [d.toString("dd.MM.yyyy") for d in s_dates]
            self.text_box.setPlainText("\n".join(lines))
    def get_selected_dates_str(self):
        return [d.toString("dd.MM.yyyy") for d in sorted(self.cal.selected_dates)]


# ------------- RIBBON / NAVBAR ---------------
class RibbonWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()
    def init_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(5,5,5,5)
        layout.setSpacing(10)
        
        #file_group = QGroupBox("Файл")
        file_group = QGroupBox("Файлы")
        file_group.setStyleSheet("""
            QGroupBox {
                border: 2px solid black;
                border-radius: 10px;
                margin-top: 2ex; /* отступ под заголовок */
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                subcontrol-position: top center;
                padding: 0 3px;
            }
        """)
        file_layout = QHBoxLayout(file_group)
        self.btn_import = QToolButton()
        self.btn_import.setText("Импорт")
        self.btn_import.setIcon(QIcon(get_image_path("import.png")))
        self.btn_import.setIconSize(QSize(24,24))
        self.btn_import.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        file_layout.addWidget(self.btn_import)

        self.btn_export = QToolButton()
        self.btn_export.setText("Экспорт")
        self.btn_export.setIcon(QIcon(get_image_path("export.png")))
        self.btn_export.setIconSize(QSize(24,24))
        self.btn_export.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        file_layout.addWidget(self.btn_export)

        self.btn_backup = QToolButton()
        self.btn_backup.setText("Резервная копия")
        self.btn_backup.setIcon(QIcon(get_image_path("backup.png")))
        self.btn_backup.setIconSize(QSize(24,24))
        self.btn_backup.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        file_layout.addWidget(self.btn_backup)

        self.btn_restore = QToolButton()
        self.btn_restore.setText("Восстановить")
        self.btn_restore.setIcon(QIcon(get_image_path("restore.png")))
        self.btn_restore.setIconSize(QSize(24,24))
        self.btn_restore.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        file_layout.addWidget(self.btn_restore)
        
        layout.addWidget(file_group)
        
        group_group = QGroupBox("Группа")
        group_group.setStyleSheet("""
            QGroupBox {
                border: 2px solid black;
                border-radius: 10px;
                margin-top: 2ex; /* отступ под заголовок */
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                subcontrol-position: top center;
                padding: 0 3px;
            }
        """)
        group_layout = QHBoxLayout(group_group)
        self.btn_add_group = QToolButton()
        self.btn_add_group.setText("Добавить группу")
        self.btn_add_group.setIcon(QIcon(get_image_path("add-group.png")))
        self.btn_add_group.setIconSize(QSize(24,24))
        self.btn_add_group.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        group_layout.addWidget(self.btn_add_group)

        self.btn_del_group = QToolButton()
        self.btn_del_group.setText("Удалить группу")
        self.btn_del_group.setIcon(QIcon(get_image_path("trash.png")))
        self.btn_del_group.setIconSize(QSize(24,24))
        self.btn_del_group.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        group_layout.addWidget(self.btn_del_group)
        
        layout.addWidget(group_group)
        
        student_group = QGroupBox("Студенты/Даты")
        student_group.setStyleSheet("""
            QGroupBox {
                border: 2px solid black;
                border-radius: 10px;
                margin-top: 2ex; /* отступ под заголовок */
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                subcontrol-position: top center;
                padding: 0 3px;
            }
        """)
        student_layout = QHBoxLayout(student_group)
        self.btn_add_students = QToolButton()
        self.btn_add_students.setText("Студенты")
        self.btn_add_students.setIcon(QIcon(get_image_path("add-user.png")))
        self.btn_add_students.setIconSize(QSize(24,24))
        self.btn_add_students.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        student_layout.addWidget(self.btn_add_students)
        
        self.btn_add_dates = QToolButton()
        self.btn_add_dates.setText("Даты")
        self.btn_add_dates.setIcon(QIcon(get_image_path("calendar.png")))
        self.btn_add_dates.setIconSize(QSize(24,24))
        self.btn_add_dates.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        student_layout.addWidget(self.btn_add_dates)
        
        layout.addWidget(student_group)
        
        calc_group = QGroupBox("Рассчитать")
        calc_group.setStyleSheet("""
            QGroupBox {
                border: 2px solid black;
                border-radius: 10px;
                margin-top: 2ex; /* отступ под заголовок */
            }
            QGroupBox::title {
                subcontrol-origin: margin;
                subcontrol-position: top center;
                padding: 0 3px;
            }
        """)
        calc_layout = QHBoxLayout(calc_group)
        self.btn_calculate = QToolButton()
        self.btn_calculate.setText("Рассчитать")
        self.btn_calculate.setIcon(QIcon(get_image_path("calc.png")))
        self.btn_calculate.setIconSize(QSize(24,24))
        self.btn_calculate.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        calc_layout.addWidget(self.btn_calculate)
        layout.addWidget(calc_group)
        
        self.btn_rupy = QToolButton()
        self.btn_rupy.setText("Rupy")
        self.btn_rupy.setIcon(QIcon(get_image_path("document.png")))
        self.btn_rupy.setIconSize(QSize(24,24))
        self.btn_rupy.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        layout.addWidget(self.btn_rupy)

class NavBarWidget(QWidget):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.init_ui()
    def init_ui(self):
        layout = QHBoxLayout(self)
        layout.setContentsMargins(5,5,5,5)
        layout.setSpacing(10)
        self.ribbon = RibbonWidget()
        layout.addWidget(self.ribbon)
        layout.addStretch()
        self.btn_settings = QToolButton()
        self.btn_settings.setText("Настройки")
        self.btn_settings.setToolTip("Настройки")
        self.btn_settings.setIcon(QIcon(get_image_path("settings.png")))
        self.btn_settings.setIconSize(QSize(24,24))
        self.btn_settings.setToolButtonStyle(Qt.ToolButtonTextUnderIcon)
        layout.addWidget(self.btn_settings)
        self.setLayout(layout)


# ------------- Главное окно приложения ---------------
class JournalApp(QMainWindow):
    def __init__(self):
        super().__init__()
        app = QApplication.instance()
        self.setWindowTitle("Электронный журнал")
        self.resize(1200,700)
        
        # Подключаемся к базе
        self.conn = sqlite3.connect(DB_NAME)
        self.cursor = self.conn.cursor()
        self.init_db()

        # Параметры
        self.current_scale = 100
        self.show_log = False
        self.disable_colors = False
        self.current_group = None
        
        self.colors = {
            "main_window_bg": QColor("#ffffff"),  # Фон приложения
            "table_bg": QColor("#ffffff"),         # Фон таблицы
            "btn_bg": QColor("#1e3c72"),           # Кнопки (синий)
            "n_cell_bg": QColor("#f0f0f0"),          # Цвет для "Н"
            "otrabotka_bg": QColor("#c8dcff"),       # Цвет для отработки
            "date_color": QColor("#7e9bb7"),         # Цвет дат (светло-голубой)
            "student_color": QColor("#ffffff"),      # Цвет студентов (светло-зелёный)
            "popup_bg": QColor("#ffffff"),           # Цвет всплывающих окон
            "icon_color": QColor("#1e3c72")          # Цвет иконок
        }

        # 2) Конфиг
        self.config_path = get_config_path()
        if not os.path.exists(self.config_path):
            self.save_settings()
        self.load_settings()  # теперь self.current_scale, show_log, disable_colors и colors могут перезаписаться из JSON

        # 3) Прокидываем флаг «без цвета» и сразу применяем всё к UI
        app.setProperty("disable_colors", self.disable_colors)
        
        font = app.font()
        font.setPointSize(int(7 * self.current_scale / 100))
        app.setFont(font)
        
        self.group_combo = QComboBox()
        self.user_column_widths = {}
        self.ignore_changes = False
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        self.main_layout = QVBoxLayout(main_widget)
        self.main_layout.setContentsMargins(0,0,0,0)
        
        self.navbar = NavBarWidget()
        self.main_layout.addWidget(self.navbar)
        
        # Привязка сигналов ribbon
        r = self.navbar.ribbon
        r.btn_import.clicked.connect(self.import_from_excel)
        r.btn_export.clicked.connect(self.export_to_excel)
        r.btn_backup.clicked.connect(self.backup_data)
        r.btn_restore.clicked.connect(self.restore_data)
        r.btn_add_group.clicked.connect(self.add_group)
        r.btn_del_group.clicked.connect(self.delete_current_group)
        r.btn_add_students.clicked.connect(self.add_students_bulk)
        r.btn_add_dates.clicked.connect(self.add_dates_multiple)
        r.btn_calculate.clicked.connect(self.calculate_ratings)
        r.btn_rupy.clicked.connect(self.open_rupy)
        
        # Кнопка настроек
        self.navbar.btn_settings.clicked.connect(self.open_settings)
        
        # Слой поиска/групп
        search_panel = QHBoxLayout()
        search_panel.setContentsMargins(10,10,10,10)
        
        lbl_group = QLabel("Группа:")
        search_panel.addWidget(lbl_group)
        self.group_combo.currentTextChanged.connect(self.refresh_table)
        search_panel.addWidget(self.group_combo)
        
        self.group_combo.setContextMenuPolicy(Qt.CustomContextMenu)
        self.group_combo.customContextMenuRequested.connect(self.on_group_combo_context_menu)

        self.include_exam = True
        self.chk_include_exam = QCheckBox("Учитывать экзамен")
        self.chk_include_exam.setChecked(True)
        self.chk_include_exam.stateChanged.connect(self.update_include_exam)
        search_panel.addWidget(self.chk_include_exam)
        
        self.include_labs = False
        self.chk_include_labs = QCheckBox("Включить лаб-ки")
        self.chk_include_labs.setChecked(False)
        self.chk_include_labs.stateChanged.connect(self.update_include_labs)
        search_panel.addWidget(self.chk_include_labs)
        
        self.include_theory = True
        self.chk_include_theory = QCheckBox("Включить теорию")
        self.chk_include_theory.setChecked(True)
        self.chk_include_theory.stateChanged.connect(self.update_include_theory)
        search_panel.addWidget(self.chk_include_theory)
        
        lbl_local = QLabel("Локальный поиск:")
        search_panel.addWidget(lbl_local)
        self.local_search_line_edit = QLineEdit()
        self.local_search_line_edit.setPlaceholderText("Имя...")
        self.local_search_line_edit.setFixedWidth(150)
        self.local_search_line_edit.textChanged.connect(self.filter_local_table)
        search_panel.addWidget(self.local_search_line_edit)
        
        lbl_global = QLabel("Глобальный поиск:")
        search_panel.addWidget(lbl_global)
        self.global_search_line_edit = QLineEdit()
        self.global_search_line_edit.setPlaceholderText("Запрос...")
        self.global_search_line_edit.setFixedWidth(150)
        search_panel.addWidget(self.global_search_line_edit)
        
        btn_global = QPushButton()
        btn_global.setIcon(QIcon(get_image_path("search.png")))
        btn_global.setFixedSize(40,30)
        btn_global.clicked.connect(self.open_global_search)
        search_panel.addWidget(btn_global)
        
        search_panel.addStretch()
        self.main_layout.addLayout(search_panel)
        
        # Сплиттер главного окна – горизонтальный
        splitter_h = QSplitter(Qt.Horizontal)
        self.main_layout.addWidget(splitter_h, stretch=1)

        # Левая панель – лог (скрывается при отключении логов)
        left_frame = QFrame()
        self.left_frame = left_frame
        left_layout = QVBoxLayout(left_frame)
        self.log_widget = QPlainTextEdit()
        self.log_widget.setReadOnly(True)
        self.log_widget.setObjectName("log_widget")
        # Вместо setVisible(self.show_log) скрываем весь left_frame
        left_frame.setVisible(self.show_log)
        left_layout.addWidget(self.log_widget, 1)
        splitter_h.addWidget(left_frame)

        # Правая панель – вертикальный сплиттер с основной и лабораторной таблицами
        right_frame = QFrame()
        right_layout = QVBoxLayout(right_frame)
        self.vertical_splitter = QSplitter(Qt.Vertical)

        self.table = UndoableTableWidget()
        # Настройки основной таблицы (теория)
        self.table.setEditTriggers(QAbstractItemView.AllEditTriggers)
        self.table.setWordWrap(True)
        self.table.verticalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        self.table.horizontalHeader().setSectionResizeMode(QHeaderView.Interactive)
        self.table.itemChanged.connect(self.on_item_changed)
        self.table.horizontalHeader().sectionResized.connect(self.on_section_resized)
        self.table.horizontalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.horizontalHeader().customContextMenuRequested.connect(self.on_col_header_context_menu)
        self.table.verticalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.verticalHeader().customContextMenuRequested.connect(self.on_row_header_context_menu)
        self.table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.table.customContextMenuRequested.connect(self.on_table_context_menu)
        self.vertical_splitter.addWidget(self.table)

        self.lab_table = UndoableTableWidget()
        # Настройки лабораторной таблицы (аналогичные основной)
        self.lab_table.setEditTriggers(QAbstractItemView.AllEditTriggers)
        self.lab_table.setWordWrap(True)
        self.lab_table.verticalHeader().setSectionResizeMode(QHeaderView.ResizeToContents)
        self.lab_table.horizontalHeader().setSectionResizeMode(QHeaderView.Interactive)
        self.lab_table.itemChanged.connect(self.on_item_changed)
        self.lab_table.horizontalHeader().sectionResized.connect(self.on_section_resized)
        self.lab_table.horizontalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.lab_table.horizontalHeader().customContextMenuRequested.connect(self.on_lab_col_header_context_menu)
        self.lab_table.verticalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.lab_table.verticalHeader().customContextMenuRequested.connect(self.on_row_header_context_menu)
        self.lab_table.setContextMenuPolicy(Qt.CustomContextMenu)
        self.lab_table.customContextMenuRequested.connect(self.on_table_context_menu)
        # Скрываем лабораторную таблицу по умолчанию
        self.lab_table.setVisible(False)
        # позволяем правый клик на заголовке lab_table
        self.lab_table.horizontalHeader().setContextMenuPolicy(Qt.CustomContextMenu)
        self.lab_table.horizontalHeader().customContextMenuRequested.connect(
            self.on_lab_col_header_context_menu
        )
        self.vertical_splitter.addWidget(self.lab_table)

        # При необходимости задайте начальные размеры вертикального сплиттера:
        self.vertical_splitter.setSizes([400, 200])
        right_layout.addWidget(self.vertical_splitter)
        splitter_h.addWidget(right_frame)

        self.set_show_log(self.show_log)
        self.update_all_icons()
        # Завершаем
        self.update_stylesheet()
        self.load_groups()
        self.refresh_table()
    
    def load_settings(self):
        import json
        try:
            with open(self.config_path, "r", encoding="utf-8") as f:
                cfg = json.load(f)
            # пример структуры cfg:
            # {
            #   "colors": { "main_window_bg": "#ffffff", … },
            #   "scale": 120,
            #   "show_log": true,
            #   "disable_colors": false
            # }
            self.colors = {k: QColor(v) for k, v in cfg.get("colors", {}).items()}
            self.current_scale = cfg.get("scale", self.current_scale)
            self.show_log      = cfg.get("show_log", self.show_log)
            self.disable_colors = cfg.get("disable_colors", self.disable_colors)
        except Exception:
            # файл не найден или битый – оставляем дефолты
            pass

    def save_settings(self):
        import json
        cfg = {
            "colors": {k: self.colors[k].name() for k in self.colors},
            "scale": self.current_scale,
            "show_log": self.show_log,
            "disable_colors": self.disable_colors
        }
        try:
            with open(self.config_path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, ensure_ascii=False, indent=2)
        except Exception as e:
            self.append_log(f"Ошибка сохранения настроек: {e}")

    # ------------------ ИНИЦИАЛИЗАЦИЯ БД ------------------
    def init_db(self):
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS groups(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_name TEXT,
                include_exam INTEGER DEFAULT 1,
                include_labs INTEGER DEFAULT 0,
                include_theory INTEGER DEFAULT 1
            )
        """)
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS students(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER,
                student_name TEXT,
                ro_value REAL,
                itog_value REAL,
                otrabotka REAL,
                exam REAL,
                letter_count INTEGER,
                r_value REAL,
                digital_equivalent REAL DEFAULT 0,
                letter_equivalent TEXT DEFAULT 'F',
                FOREIGN KEY(group_id) REFERENCES groups(id)
            )
        """)
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS dates(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                group_id INTEGER,
                date_label TEXT,
                FOREIGN KEY(group_id) REFERENCES groups(id)
            )
        """)
        self.cursor.execute("""
            CREATE TABLE IF NOT EXISTS grades(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                student_id INTEGER,
                date_id INTEGER,
                grade TEXT,
                FOREIGN KEY(student_id) REFERENCES students(id),
                FOREIGN KEY(date_id) REFERENCES dates(id)
            )
        """)
        # Добавление колонки notes, если её нет
        self.cursor.execute("PRAGMA table_info(dates)")
        cols = [c[1].lower() for c in self.cursor.fetchall()]
        if 'notes' not in cols:
            self.cursor.execute("ALTER TABLE dates ADD COLUMN notes TEXT")
        # Колонки include_labs и include_theory уже задаются по умолчанию при создании таблицы
        self.cursor.execute("PRAGMA table_info(groups)")
        if 'group_type' not in [c[1].lower() for c in self.cursor.fetchall()]:
            # если столбца ещё нет – добавляем. Значение по умолчанию 'classic'
            self.cursor.execute("ALTER TABLE groups ADD COLUMN group_type TEXT DEFAULT 'classic'")
        self.conn.commit()

    def on_group_combo_context_menu(self, pos):
        """Показать контекстное меню при щёлканье правой кнопкой по комбобоксу с группами."""
        # Определяем индекс под мышью
        index = self.group_combo.view().indexAt(pos)
        if not index.isValid():
            return
        
        # Узнаём, какая группа сейчас под курсором
        gname = self.group_combo.itemText(index.row())
        if not gname:
            return
        
        menu = QMenu(self)
        
        act_change = menu.addAction("Изменить тип группы...")
        
        chosen = menu.exec_(self.group_combo.mapToGlobal(pos))
        if chosen == act_change:
            self.change_group_type(gname)
    
    def change_group_type(self, group_name):
        """Открыть диалог, выбрать новый тип (classic или lab), обновить запись в БД."""
        # Сперва получим текущий тип из БД
        self.cursor.execute("SELECT group_type FROM groups WHERE group_name=?", (group_name,))
        row = self.cursor.fetchone()
        if not row:
            return
        old_type = row[0] or "classic"  # бывает None
        
        # Создадим простой диалог с QComboBox для выбора
        dlg = QDialog(self)
        dlg.setWindowTitle(f"Изменить тип группы «{group_name}»")
        lay = QVBoxLayout(dlg)
        
        lbl = QLabel("Выберите новый тип:")
        lay.addWidget(lbl)
        cb = QComboBox()
        cb.addItems(["Классика", "Лаб/Практ"])
        # Сопоставим "classic" -> "Классика", "lab" -> "Лаб/Практ"
        if old_type == "lab":
            cb.setCurrentText("Лаб/Практ")
        else:
            cb.setCurrentText("Классика")
        lay.addWidget(cb)
        
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        lay.addWidget(btn_box)
        btn_box.accepted.connect(dlg.accept)
        btn_box.rejected.connect(dlg.reject)
        
        if dlg.exec_() == QDialog.Accepted:
            new_ui_type = cb.currentText()  # "Классика" или "Лаб/Практ"
            if new_ui_type == "Лаб/Практ":
                db_type = "lab"
            else:
                db_type = "classic"
            
            # Записываем в БД
            self.cursor.execute(
                "UPDATE groups SET group_type=? WHERE group_name=?",
                (db_type, group_name)
            )
            self.conn.commit()
            
            self.append_log(f"Группа {group_name}: сменили тип -> {db_type}")
            
            # Если именно эту группу мы сейчас смотрим, то обновим таблицу
            if self.group_combo.currentText() == group_name:
                self.refresh_table()

    # ------------------ ОБНОВЛЕНИЕ СТИЛЯ ------------------
    
    def update_all_icons(self):
        # Получаем новый цвет для иконок из настроек
        icon_color = self.colors.get("icon_color", QColor("#1e3c72"))

        # Список пар: (имя кнопки, путь к оригинальной PNG)
        icons_info = [
            (self.navbar.ribbon.btn_import, "import.png"),
            (self.navbar.ribbon.btn_export, "export.png"),
            (self.navbar.ribbon.btn_backup, "backup.png"),
            (self.navbar.ribbon.btn_restore, "restore.png"),
            (self.navbar.ribbon.btn_add_group, "add-group.png"),
            (self.navbar.ribbon.btn_del_group, "trash.png"),
            (self.navbar.ribbon.btn_add_students, "add-user.png"),
            (self.navbar.ribbon.btn_add_dates, "calendar.png"),
            (self.navbar.ribbon.btn_calculate, "calc.png"),
            (self.navbar.ribbon.btn_rupy, "document.png"),
            (self.navbar.btn_settings, "settings.png"),
            (self.global_search_line_edit.parent().findChild(QPushButton), "search.png")
        ]

        for btn, img_name in icons_info:
            path = get_image_path(img_name)
            pixmap = QPixmap(path)
            if not pixmap.isNull():
                new_icon = tint_icon(pixmap, icon_color)
                btn.setIcon(new_icon)

    def update_stylesheet(self):
        main_bg = self.colors.get("main_window_bg", QColor("#fafbfd")).name()
        btn_bg = self.colors.get("btn_bg", QColor("#1e3c72")).name()
        popup_bg = self.colors.get("popup_bg", QColor("#ffffff")).name()
        # Пример простого QSS для главного окна и кнопок:
        qss = f"""
        QMainWindow {{
            background-color: {main_bg};
        }}
        QPushButton, QToolButton {{
            background-color: {btn_bg};
            color: #fff;
        }}
        QDialog {{
            background-color: {popup_bg};
        }}
        """
        self.setStyleSheet(qss)
        
        if self.disable_colors:
            # Если отключаем цвета, то у таблицы фон серый
            self.table.setStyleSheet("QTableWidget { background-color: #DDDDDD; }")
        else:
            # Иначе берём цвет фона таблицы из словаря
            tbl_bg = self.colors.get("table_bg", QColor("white")).name()
            self.table.setStyleSheet(f"QTableWidget {{ background-color: {tbl_bg}; }}")

    # ------------------ ОТКРЫТИЕ НАСТРОЕК ------------------
    def open_settings(self):
        dlg = SettingsDialog(
            current_scale=self.current_scale,
            show_log=self.show_log,
            disable_colors=self.disable_colors,
            colors=self.colors,
            parent=self
        )
        if dlg.exec_() == QDialog.Accepted:
            self.current_scale = dlg.get_scale_value()
            self.show_log = dlg.get_show_log_value()
            self.disable_colors = dlg.get_disable_colors_value()

            # Обновляем словарь цветов
            self.colors = dlg.get_colors()

            scale = self.current_scale

            # Применяем масштаб: изменяем размер шрифта всего приложения
            
            self.default_col_width = int(180 * (scale / 100.0))
            for btn in self.findChildren(QToolButton):
                try:
                    btn.setIconSize(QSize(int(24 * scale / 100), int(24 * scale / 100)))
                except RuntimeError:
                    continue
            self.updateGeometry()
            self.repaint()
            new_font_size = int(7 * scale / 100)  # базовый размер 13, масштабируется пропорционально
            app = QApplication.instance()
            font = app.font()
            font.setPointSize(new_font_size)
            app.setFont(font)

            self.save_settings()    
            self.set_show_log(self.show_log)
            self.update_stylesheet()
            self.update_all_icons()
            self.refresh_table()

    
    # ------------------ ЖУРНАЛ ДЕЙСТВИЙ ------------------
    def set_show_log(self, flag):
        self.show_log = flag
        if hasattr(self, 'left_frame'):
            self.left_frame.setVisible(flag)
        if flag:
            self.append_log("Журнал действий включён")
    
    def append_log(self, msg):
        if self.show_log:
            from datetime import datetime
            t_str = datetime.now().strftime("[%H:%M:%S]")
            self.log_widget.appendPlainText(f"{t_str} {msg}")
    
    # ------------------ ГРУППЫ ------------------
    def load_groups(self):
        """Заполняет выпадающий список только «базовыми»
        (теоретическими) группами, отфильтровывая все,
        чьё имя оканчивается на '_Лаб'."""
        self.group_combo.clear()
    
        # берём все имена групп из БД
        self.cursor.execute("SELECT group_name FROM groups ORDER BY group_name")
        for (gname,) in self.cursor.fetchall():
            if not gname.endswith("_Лаб"):          # <- фильтр
                self.group_combo.addItem(gname)
    
    def add_group(self):
        dlg = QDialog(self)
        dlg.setWindowTitle("Создать группу")
        layout = QVBoxLayout(dlg)
    
        lbl_name = QLabel("Название группы:")
        layout.addWidget(lbl_name)
        le_name = QLineEdit()
        layout.addWidget(le_name)
    
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        layout.addWidget(btn_box)
        btn_box.accepted.connect(dlg.accept)
        btn_box.rejected.connect(dlg.reject)
    
        if dlg.exec_() == QDialog.Accepted:
            gname = le_name.text().strip()
            if not gname:
                return
                
            # Создаем основную группу (теория) с включёнными экзаменом и теорией по умолчанию, лабки отключены
            self.cursor.execute(
                "INSERT INTO groups(group_name, group_type, include_exam, include_theory, include_labs) VALUES(?,?,?,?,?)",
                (gname, "classic", 1, 1, 0)
            )
            
            # Создаем зеркальную лабораторную группу
            lab_name = f"{gname}_Лаб"
            self.cursor.execute(
                "INSERT INTO groups(group_name, group_type) VALUES(?,?)",
                (lab_name, "lab")
            )
            
            self.conn.commit()
            self.load_groups()
            self.group_combo.setCurrentText(gname)
            self.refresh_table()
            self.append_log(f"Добавлена группа: {gname} (теория) и {lab_name} (лабки)")

    
    def delete_current_group(self):
        gname = self.group_combo.currentText().strip()
        if not gname:
            return

        lab_name = f"{gname}_Лаб"        # имя зеркальной группы

        ans = QMessageBox.question(
            self,
            "Удалить группу?",
            f"Удалить «{gname}» и связанную «{lab_name}»?",
            QMessageBox.Yes | QMessageBox.No,
            QMessageBox.No
        )
        if ans != QMessageBox.Yes:
            return

        # --- собираем id обеих групп, если существуют
        self.cursor.execute(
            "SELECT id, group_name FROM groups "
            "WHERE group_name IN (?, ?)", (gname, lab_name)
        )
        rows = self.cursor.fetchall()            # [(id, name), …]

        for group_id, grp in rows:

            # 1) даты и оценки по датам
            self.cursor.execute("SELECT id FROM dates WHERE group_id=?", (group_id,))
            for (date_id,) in self.cursor.fetchall():
                self.cursor.execute("DELETE FROM grades WHERE date_id=?", (date_id,))
            self.cursor.execute("DELETE FROM dates WHERE group_id=?", (group_id,))

            # 2) студенты и их оценки
            self.cursor.execute("SELECT id FROM students WHERE group_id=?", (group_id,))
            for (stud_id,) in self.cursor.fetchall():
                self.cursor.execute("DELETE FROM grades WHERE student_id=?", (stud_id,))
            self.cursor.execute("DELETE FROM students WHERE group_id=?", (group_id,))

            # 3) сама группа
            self.cursor.execute("DELETE FROM groups WHERE id=?", (group_id,))
            self.append_log(f"Группа «{grp}» удалена каскадно.")

        self.conn.commit()

        # обновляем UI
        self.load_groups()
        if self.group_combo.count():
            self.group_combo.setCurrentIndex(0)
        else:
            self.table.clear()
    
    # ------------------ МЕТОДЫ ДЛЯ ДАТ ------------------
    def add_dates_multiple(self):
        dlg = MultiCalendarDialog(self)
        if dlg.exec_() == QDialog.Accepted:
            dates_list = dlg.get_selected_dates_str()
            if not dates_list:
                return
            gname = self.group_combo.currentText().strip()
            if not gname:
                return
            # Запрашиваем выбор у пользователя
            from PyQt5.QtWidgets import QInputDialog
            items = ["Теория", "Лабки", "Обе"]
            item, ok = QInputDialog.getItem(self, "Добавление дат", "Выберите группу для добавления дат:", items, 0, False)
            if not ok:
                return
            target_theory = False
            target_labs = False
            if item == "Теория":
                target_theory = True
            elif item == "Лабки":
                target_labs = True
            elif item == "Обе":
                target_theory = True
                target_labs = True
            # Получаем id основной группы (теории)
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (gname,))
            row_g = self.cursor.fetchone()
            if not row_g:
                return
            theory_group_id = row_g[0]
            # Получаем id лабораторной группы, если существует
            lab_name = f"{gname}_Лаб"
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_name,))
            row_lab = self.cursor.fetchone()
            lab_group_id = row_lab[0] if row_lab else None
            added = 0
            def add_dates_to_group(group_id):
                nonlocal added
                for base_str in dates_list:
                    d_str = base_str
                    suffix_num = 1
                    while True:
                        self.cursor.execute("SELECT 1 FROM dates WHERE group_id=? AND date_label=?", (group_id, d_str))
                        if not self.cursor.fetchone():
                            self.cursor.execute("INSERT INTO dates(group_id,date_label) VALUES(?,?)", (group_id, d_str))
                            added += 1
                            break
                        else:
                            suffix_num += 1
                            d_str = f"{base_str}|п{suffix_num}"
            if target_theory:
                add_dates_to_group(theory_group_id)
            if target_labs and lab_group_id:
                add_dates_to_group(lab_group_id)
            if added > 0:
                self.conn.commit()
                self.refresh_table()
            self.append_log(f"Добавлено дат: {added}")
    
    def date_sort_key(self, d_label):
        parts = d_label.split("|п")
        base_date_str = parts[0].strip()
        suffix_num = 0
        if len(parts) > 1:
            try:
                suffix_num = int(parts[1])
            except:
                suffix_num = 9999
        from datetime import datetime
        try:
            dt = datetime.strptime(base_date_str, "%d.%m.%Y")
            return (dt.timestamp(), suffix_num)
        except:
            return (999999999, suffix_num)
        
    # ------------------ МЕТОДЫ ДЛЯ СТУДЕНТОВ ------------------
    def add_students_bulk(self):
        dlg = QDialog(self)
        dlg.setWindowTitle("Добавить студентов")
        dlg.resize(400,300)
        lay = QVBoxLayout(dlg)
        lbl = QLabel("Введите студентов,\nпо одному на каждой строке:")
        lay.addWidget(lbl)
        text_ed = QPlainTextEdit()
        lay.addWidget(text_ed)
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        lay.addWidget(btn_box)
        btn_box.accepted.connect(dlg.accept)
        btn_box.rejected.connect(dlg.reject)
        if dlg.exec_() == QDialog.Accepted:
            lines = [l.strip() for l in text_ed.toPlainText().split("\n") if l.strip()]
            if not lines:
                return
            gname = self.group_combo.currentText().strip()
            if not gname:
                return

            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (gname,))
            row_g = self.cursor.fetchone()
            if not row_g:
                return
            group_id = row_g[0]

            cnt_added = 0
            for sname in lines:
                # Добавляем в текущую группу
                self.cursor.execute(
                    "SELECT id FROM students WHERE group_id=? AND lower(student_name)=lower(?)",
                    (group_id, sname.lower())
                )
                row_s = self.cursor.fetchone()
                if not row_s:
                    self.cursor.execute(
                        """INSERT INTO students 
                           (group_id, student_name, ro_value, itog_value, otrabotka, exam, letter_count, r_value)
                           VALUES(?,?,?,?,?,?,?,?)""",
                        (group_id, sname, 0,0,0,0,0,0)
                    )
                    cnt_added += 1

            # Сохраняем
            if cnt_added > 0:
                self.conn.commit()

            # Теперь синхронизируем с параллельной группой
            # 1) Определяем base_name (без _lab/prakt)
            parallel_gname = get_parallel_group_name(gname)

            # если пара найдена и существует – добавляем тех же студентов
            if parallel_gname and parallel_gname != gname:
                self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (parallel_gname,))
                row_p = self.cursor.fetchone()
                if row_p:
                    p_group_id = row_p[0]
                    for sname in lines:
                        self.cursor.execute(
                            "SELECT 1 FROM students WHERE group_id=? AND lower(student_name)=lower(?)",
                            (p_group_id, sname.lower())
                        )
                        if not self.cursor.fetchone():
                            self.cursor.execute(
                                """INSERT INTO students
                                (group_id, student_name, ro_value, itog_value,
                                otrabotka, exam, letter_count, r_value)
                                VALUES(?,?,?,?,?,?,?,?)""",
                                (p_group_id, sname, 0, 0, 0, 0, 0, 0)
                            )
                    self.conn.commit()
                    self.append_log(f"(Синхронизировано) Добавлено студентов в {parallel_gname}")
        self.refresh_table()
    
    def add_student(self):
        dlg = QDialog(self)
        dlg.setWindowTitle("Добавить студента")
        layout = QVBoxLayout(dlg)
    
        lbl_name = QLabel("Имя студента:")
        layout.addWidget(lbl_name)
        le_name = QLineEdit()
        layout.addWidget(le_name)
    
        btn_box = QDialogButtonBox(QDialogButtonBox.Ok | QDialogButtonBox.Cancel)
        layout.addWidget(btn_box)
        btn_box.accepted.connect(dlg.accept)
        btn_box.rejected.connect(dlg.reject)
    
        if dlg.exec_() == QDialog.Accepted:
            student_name = le_name.text().strip()
            if not student_name:
                return
            
            # Получаем имя выбранной основной группы (теория)
            gname = self.group_combo.currentText().strip()
            if not gname:
                return
            
            # Добавляем студента в основную группу (теория)
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (gname,))
            row = self.cursor.fetchone()
            if row:
                theory_group_id = row[0]
                self.cursor.execute(
                    "INSERT INTO students(group_id, student_name) VALUES(?,?)",
                    (theory_group_id, student_name)
                )
            else:
                self.append_log(f"Ошибка: не найдена группа {gname}")
                return
            
            # Пробуем добавить студента в лабораторную группу,
            # если такая существует (с именем "<теория>_Лаб")
            lab_name = f"{gname}_Лаб"
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_name,))
            row_lab = self.cursor.fetchone()
            if row_lab:
                lab_group_id = row_lab[0]
                self.cursor.execute(
                    "INSERT INTO students(group_id, student_name) VALUES(?,?)",
                    (lab_group_id, student_name)
                )
            else:
                self.append_log(f"Лабораторная группа не найдена для {gname}")
            
            self.conn.commit()
            # Обновляем отображение студентов и таблиц
            self.refresh_table()            
            self.append_log(f"Добавлен студент: {student_name} в {gname} и {lab_name if row_lab else 'нет группы лабок'}")

    # ------------------ ЧЕКБОКС "УЧИТЫВАТЬ ЭКЗАМЕН" ------------------
    def update_include_exam(self, state):
        """Обработчик переключения учёта экзамена"""
        gname = self.group_combo.currentText().strip()
        if not gname:
            return
        include_exam = 1 if state == Qt.Checked else 0
        self.cursor.execute("UPDATE groups SET include_exam=? WHERE group_name=?", (include_exam, gname))
        self.conn.commit()
        self.include_exam = (include_exam == 1)
        self.append_log(f"Учёт экзамена: {'включен' if include_exam else 'выключен'}")
        self.calculate_ratings()
        self.refresh_table()

    def update_include_labs(self, state):
        gname = self.group_combo.currentText().strip()
        if not gname:
            return
        include_labs = 1 if state == Qt.Checked else 0
        self.cursor.execute("UPDATE groups SET include_labs=? WHERE group_name=?", (include_labs, gname))
        self.conn.commit()
        self.include_labs = (include_labs == 1)
        self.append_log(f"Включить лаб-ки: {bool(self.include_labs)}, для группы '{gname}'")
        self.calculate_ratings()
        self.refresh_table()

    def update_include_theory(self, state):
        gname = self.group_combo.currentText().strip()
        if not gname:
            return
        include_theory = 1 if state == Qt.Checked else 0
        self.cursor.execute("UPDATE groups SET include_theory=? WHERE group_name=?", (include_theory, gname))
        self.conn.commit()
        self.include_theory = (include_theory == 1)
        self.append_log(f"Включить теорию: {self.include_theory} для группы '{gname}'")
        self.calculate_ratings()
        self.refresh_table()
    
    # ------------------ ОСНОВНОЙ МЕТОД REFRESH_TABLE ------------------
    def refresh_table(self):
        """Перестраивает таблицы при любом изменении переключателей
        или смене выбранной группы."""
        self.ignore_changes = True
        h_pos = self.table.horizontalScrollBar().value()
        v_pos = self.table.verticalScrollBar().value()

        try:
            self.table.itemChanged.disconnect(self.on_item_changed)
        except Exception:
            pass
        self.table.blockSignals(True)

        self.table.clear()
        gname = self.group_combo.currentText().strip()
        if not gname:                          # нет выбранной группы
            self.table.setRowCount(0)
            self.table.setColumnCount(0)
            self.table.blockSignals(False)
            self.table.itemChanged.connect(self.on_item_changed)
            return

        # --- параметры группы -------------------------------------------------
        self.cursor.execute("""
            SELECT id, include_exam, include_labs, include_theory
            FROM groups WHERE group_name=?""", (gname,))
        row = self.cursor.fetchone()
        if not row:                            # группа удалена - пока мы смотрели
            self.table.blockSignals(False)
            self.table.itemChanged.connect(self.on_item_changed)
            return

        group_id, fl_exam, fl_labs, fl_theory = row
        self.include_exam   = bool(fl_exam)
        self.include_labs   = bool(fl_labs)
        self.include_theory = bool(fl_theory)

        # синхронизируем чек-боксы, но без обратных сигналов
        for chk, flag in (
            (self.chk_include_exam,   self.include_exam),
            (self.chk_include_labs,   self.include_labs),
            (self.chk_include_theory, self.include_theory),
        ):
            chk.blockSignals(True)
            chk.setChecked(flag)
            chk.blockSignals(False)

        is_lab_group = gname.endswith('_Лаб')

        # ================= ЛАБОРАТОРНАЯ ГРУППА ===========================
        if is_lab_group:
            self.table.setVisible(False)
            self.lab_table.setVisible(True)
            self.load_lab_table(group_id)

            self.table.blockSignals(False)
            self.table.itemChanged.connect(self.on_item_changed)
            self.update_stylesheet()
            self.ignore_changes = False
            return

        # ================ БАЗОВАЯ (ТЕОРИЯ) ГРУППА ========================

        # ---- ВИДИМОСТЬ --------------------------------------------------
        self.table.setVisible(self.include_theory)

        if self.include_labs:
            lab_name = f"{gname}_Лаб"
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_name,))
            row_lab = self.cursor.fetchone()
            if row_lab:
                self.lab_table.setVisible(True)
                self.load_lab_table(row_lab[0])
            else:
                self.lab_table.setVisible(False)
        else:
            self.lab_table.setVisible(False)

        if not self.include_theory:            # теория выключена
            self.table.blockSignals(False)
            self.table.itemChanged.connect(self.on_item_changed)
            self.update_stylesheet()
            self.ignore_changes = False
            return

        # ---- ЗАГОЛОВКИ --------------------------------------------------
        self.cursor.execute("""
            SELECT id, date_label, COALESCE(notes,'')
            FROM dates WHERE group_id=?""", (group_id,))
        d_rows = sorted(self.cursor.fetchall(), key=lambda x: self.date_sort_key(x[1]))
        self.date_columns = d_rows

        spec = ["letter_count", "ro_value", "otrabotka", "r_value"]
        if self.include_exam:
            spec += ["exam"]
        spec += ["itog_value"]
        self.student_fields = spec 

        headers = (
            ["Студент"] +
            [
                f"{label}\n{note}" if note else label
                for (_id, label, note) in d_rows
            ] +
            [class_names_rus.get(f, f) for f in spec] +
            ["Циф. экв.", "Бук. экв."]
        )
        self.table.setColumnCount(len(headers))
        self.table.setHorizontalHeaderLabels(headers)

        # ---- ДАННЫЕ СТУДЕНТОВ ------------------------------------------
        self.cursor.execute("""
            SELECT id, student_name, letter_count, ro_value,
                   otrabotka, r_value, exam, itog_value,
                   digital_equivalent, letter_equivalent
            FROM students
            WHERE group_id=?
            ORDER BY student_name""", (group_id,))
        st_rows = self.cursor.fetchall()
        self.table.setRowCount(len(st_rows))

        for r, st in enumerate(st_rows):
            (sid, name, n_cnt, ro, o_val, r_val,
             exam_val, it_val, dig, let) = st

            # имя
            item = QTableWidgetItem(name)
            item.setData(Qt.UserRole, sid)
            self.table.setItem(r, 0, item)

            # оценки по датам
            for c, (did, _, _) in enumerate(d_rows, 1):
                self.cursor.execute(
                    "SELECT grade FROM grades WHERE student_id=? AND date_id=?",
                    (sid, did))
                g = self.cursor.fetchone()
                grade = g[0] if g else ""
                cell = QTableWidgetItem(str(grade))
                cell.setTextAlignment(Qt.AlignCenter)
                if not self.disable_colors:
                    if str(grade).upper() == 'Н':
                        cell.setBackground(self.colors.get("n_cell_bg", QColor("#f0f0f0")))
                    else:
                        clr = get_grade_color(grade)
                        if clr:
                            cell.setBackground(clr)
                self.table.setItem(r, c, cell)

            offset = 1 + len(d_rows)
            spec_values = [n_cnt, ro, o_val, r_val]
            if self.include_exam:
                spec_values.append(exam_val)
            spec_values.append(it_val)

            editable_spec_indices = [2]             # O
            if self.include_exam:
                # индекс7 "Exam" находится сразу после R (т.е. 4)
                editable_spec_indices.append(4)

            for i, val in enumerate(spec_values):
                cell = QTableWidgetItem(f"{val:.2f}" if isinstance(val, float) else str(val))
                cell.setTextAlignment(Qt.AlignCenter)
            
                # оставляем редактирование только для O и Exam
                if (i not in editable_spec_indices) or (i == 2 and n_cnt == 0):
                    cell.setFlags(cell.flags() & ~Qt.ItemIsEditable)
            
                self.table.setItem(r, offset + i, cell)

            # эквиваленты (всегда только-для-чтения)
            dig_item = QTableWidgetItem(f"{dig:.2f}")
            dig_item.setFlags(dig_item.flags() & ~Qt.ItemIsEditable)
            let_item = QTableWidgetItem(let or "F")
            let_item.setFlags(let_item.flags() & ~Qt.ItemIsEditable)
            self.table.setItem(r, self.table.columnCount() - 2, dig_item)
            self.table.setItem(r, self.table.columnCount() - 1, let_item)

        # ---- финиш ------------------------------------------------------
        self.table.blockSignals(False)
        self.table.itemChanged.connect(self.on_item_changed)
        self.filter_local_table()
        self.update_stylesheet()
        self.table.horizontalScrollBar().setValue(h_pos)
        self.table.verticalScrollBar().setValue(v_pos)
        self.ignore_changes = False
    
    def load_lab_table(self, lab_group_id: int) -> None:
        """Заполняет self.lab_table для выбранной лабораторной группы."""
        # ---------- подготовка -------------------------------------------------
        try:
            self.lab_table.itemChanged.disconnect(self.on_item_changed)
        except Exception:
            pass
        
        self.lab_table.blockSignals(True)
        self.lab_table.clear()
    
        # ---------- даты (столбцы-оценок) -------------------------------------
        self.cursor.execute("""
            SELECT id, date_label, COALESCE(notes,'')
              FROM dates
             WHERE group_id=?""", (lab_group_id,))
        d_rows = sorted(self.cursor.fetchall(), key=lambda x: self.date_sort_key(x[1]))
        self.date_columns_lab = d_rows                       # сохранится для других методов
        dates_cnt = len(d_rows)
    
        # ---------- шапка таблицы ---------------------------------------------
        special_fields = ["letter_count", "ro_value", "otrabotka", "r_value"]
        spec_headers   = [class_names_rus.get(f, f) for f in special_fields]
    
        col_labels = ["Студент"]
        for did, d_lbl, d_note in d_rows:
            col_labels.append(f"{d_lbl}\n{d_note}" if d_note else d_lbl)
        col_labels += spec_headers + ["Циф. экв.", "Бук. экв."]
    
        self.lab_table.setColumnCount(len(col_labels))
        self.lab_table.setHorizontalHeaderLabels(col_labels)
    
        # ---------- сами студенты ---------------------------------------------
        self.cursor.execute("""
            SELECT id, student_name, letter_count, ro_value,
                   otrabotka, r_value, digital_equivalent, letter_equivalent
              FROM students
             WHERE group_id=?
          ORDER BY student_name""", (lab_group_id,))
        st_rows = self.cursor.fetchall()
        self.lab_table.setRowCount(len(st_rows))
    
        # --- индексы вспомогательных столбцов
        idx_first_spec = 1 + dates_cnt              # «Н»
        idx_otrabotka  = idx_first_spec + 2         # «О»  (Студент | даты | Н | РО | **О** | …)
        idx_dig        = self.lab_table.columnCount() - 2
        idx_let        = self.lab_table.columnCount() - 1
    
        # ---------- заполнение -------------------------------------------------
        for row, (sid, name, n_cnt, ro, o_val, r_val, dig, let) in enumerate(st_rows):
        
            # -- имя ------------------------------------------------------------
            item = QTableWidgetItem(name)
            item.setData(Qt.UserRole, sid)
            self.lab_table.setItem(row, 0, item)
    
            # -- оценки по датам ------------------------------------------------
            for col, (did, _, _) in enumerate(d_rows, 1):
                self.cursor.execute("""
                    SELECT grade FROM grades
                     WHERE student_id=? AND date_id=?""", (sid, did))
                grade = (self.cursor.fetchone() or [""])[0]
    
                itm = QTableWidgetItem(str(grade))
                itm.setTextAlignment(Qt.AlignCenter)
    
                if not self.disable_colors:
                    if str(grade).upper() == "Н":
                        itm.setBackground(self.colors.get("n_cell_bg", QColor("#FFF1F1")))
                    else:
                        clr = get_grade_color(grade)
                        if clr:
                            itm.setBackground(clr)
    
                self.lab_table.setItem(row, col, itm)
    
            # -- спец-поля Н, РО, О, Р ----------------------------------------
            spec_vals = [n_cnt, ro, o_val, r_val]
            for i, val in enumerate(spec_vals):
                itm = QTableWidgetItem(f"{val:.2f}" if isinstance(val, float) else str(val))
                itm.setTextAlignment(Qt.AlignCenter)
    
                # поле O (i==2) редактируемо, только если есть Н-ки
                if not (i == 2 and n_cnt > 0):
                    itm.setFlags(itm.flags() & ~Qt.ItemIsEditable)
    
                self.lab_table.setItem(row, idx_first_spec + i, itm)
    
            # -- эквиваленты ----------------------------------------------------
            itm_dig = QTableWidgetItem(f"{dig:.2f}")
            itm_dig.setFlags(itm_dig.flags() & ~Qt.ItemIsEditable)
            itm_let = QTableWidgetItem(let or "F")
            itm_let.setFlags(itm_let.flags() & ~Qt.ItemIsEditable)
    
            self.lab_table.setItem(row, idx_dig, itm_dig)
            self.lab_table.setItem(row, idx_let, itm_let)
    
        # ---------- права на редактирование -----------------------------------
        rows = self.lab_table.rowCount()
        cols = self.lab_table.columnCount()
        for r in range(rows):
            for c in range(cols):
                itm = self.lab_table.item(r, c)
                if itm is None:
                    continue
                # оценки и «Отработка» должны быть редактируемыми
                if 1 <= c <= dates_cnt or c == idx_otrabotka:
                    itm.setFlags(itm.flags() | Qt.ItemIsEditable)
                else:
                    itm.setFlags(itm.flags() & ~Qt.ItemIsEditable)
    
        # ---------- финал ------------------------------------------------------
        self.lab_table.blockSignals(False)
        self.lab_table.itemChanged.connect(self.on_item_changed)

    # ------------------ ФИЛЬТР ЛОКАЛЬНОГО ПОИСКА ------------------
    def filter_local_table(self):
        text = self.local_search_line_edit.text().strip().lower()
        for r in range(self.table.rowCount()):
            item = self.table.item(r, 0)
            if item:
                st_name = item.text().lower()
                self.table.setRowHidden(r, (text not in st_name))
    
    # ------------------ РЕАКЦИЯ НА ИЗМЕНЕНИЯ В ЯЧЕЙКЕ ------------------
    def on_item_changed(self, item):
        sender = self.sender()
        if sender == self.lab_table:
            self.on_lab_item_changed(item)
        else:
            self.on_cell_edit_commit(item.row(), item.column(), item.text().strip())
    
    def on_cell_edit_commit(self, row, col, new_val):
        """
        Обработка изменений в основной (теоретической) таблице.
        • Для числовых полей (оценки, Отработка, Экзамен) при вводе
          не-числа → 0, при вводе >100 → 100.
        """
        gname = self.group_combo.currentText().strip()
        if not gname:
            return

        self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (gname,))
        group_id_row = self.cursor.fetchone()
        if not group_id_row:
            return
        group_id = group_id_row[0]

        sid_item = self.table.item(row, 0)
        if not sid_item:
            return

        # ------------------------------------------------- имя студента
        if col == 0:
            sid = sid_item.data(Qt.UserRole)
            if sid is None:
                return
            self.cursor.execute("UPDATE students SET student_name=? WHERE id=?", (new_val, sid))
            self.conn.commit()
            self.append_log(f"Изменено имя студента: {new_val}")
            self.recalc_whole_pair(group_id)
            return

        # ------------------------------------------------- вспомогательные данные
        student_name = sid_item.text()
        self.cursor.execute("SELECT id FROM students WHERE group_id=? AND student_name=?",
                            (group_id, student_name))
        row_s = self.cursor.fetchone()
        if not row_s:
            return
        sid = row_s[0]

        date_cnt = len(self.date_columns)

        # ===== 1.  Оценки по датам =====================================
        if 1 <= col < 1 + date_cnt:
            date_idx = col - 1
            date_id, date_lbl, _ = self.date_columns[date_idx]

            # ―― валидация значения ――――――――――――――――――――――――――――――――――――――
            try:
                val = float(new_val.replace(',', '.'))
                if val > 100:
                    val = 100
            except ValueError:
                # допускаем «Н» (н/я). Всё остальное – пусто
                if new_val.strip().upper() == 'Н':
                    val = 'Н'
                else:
                    val = ""
            new_str = str(int(val)) if isinstance(val, float) and val.is_integer() else str(val)

            # запись в БД
            self.cursor.execute("SELECT id FROM grades WHERE student_id=? AND date_id=?", (sid, date_id))
            row_gr = self.cursor.fetchone()
            if row_gr:
                self.cursor.execute("UPDATE grades SET grade=? WHERE id=?", (new_str, row_gr[0]))
            else:
                self.cursor.execute("INSERT INTO grades(student_id, date_id, grade) VALUES(?,?,?)",
                                    (sid, date_id, new_str))
            # графически отражаем возможное исправление
            if new_str != new_val:
                self.ignore_changes = True
                self.table.item(row, col).setText(new_str)
                self.ignore_changes = False

        # ===== 2.  Спец-столбцы (Н, RO, **O**, R, Exam, Итог) ==========
        else:
            offset      = 1 + date_cnt
            sf_index    = col - offset
            if sf_index < 0 or sf_index >= len(self.student_fields):
                return
            field_name  = self.student_fields[sf_index]

            # ---- только числовые поля, требующие валидации -------------
            numeric_fields = {"otrabotka", "exam"}
            if field_name in numeric_fields:
                try:
                    fv = float(new_val.replace(',', '.'))
                except ValueError:
                    fv = 0.0
                if fv > 100:
                    fv = 100.0
                new_val_db = fv
                # сразу корректируем текст в таблице (до 2-х знаков)
                fixed_text = f"{fv:.0f}" if fv.is_integer() else f"{fv:.2f}"
                if fixed_text != new_val:
                    self.ignore_changes = True
                    self.table.item(row, col).setText(fixed_text)
                    self.ignore_changes = False
            else:
                # остальные поля не редактируются пользователем,
                # сюда мы попасть не должны
                return

            self.cursor.execute(f"UPDATE students SET {field_name}=? WHERE id=?",
                                (new_val_db, sid))

        # ---- фиксация изменений и пересчёт -----------------------------
        self.conn.commit()
        self.recalc_whole_pair(group_id)
        self.refresh_table()
    
    # ─────────────────────────────────────────────────────────────
    #  Пересчёт всей выбранной группы и её пары (теория / «…_Лаб»)
    # ─────────────────────────────────────────────────────────────
    def calculate_ratings(self):
        gname = self.group_combo.currentText().strip()
        if not gname:
            return

        # --- параметры текущей группы ---------------------------------
        self.cursor.execute(
            "SELECT id, include_exam, include_labs, include_theory "
            "FROM groups WHERE group_name=?", (gname,))
        row = self.cursor.fetchone()
        if not row:
            return

        group_id, fl_exam, fl_labs, fl_theory = row
        base_is_lab   = gname.endswith("_Лаб")
        include_exam  = bool(fl_exam)
        include_labs  = bool(fl_labs) and not base_is_lab     # в теории «подтягиваем» лабки
        include_theor = bool(fl_theory) or base_is_lab        # в лабах теорию не считаем

        # --- словарь «имя → id» для лабораторной пары -----------------
        lab_group_id  = None
        lab_ids_by_name = {}
        if include_labs:
            lab_name = f"{gname}_Лаб"
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_name,))
            rr = self.cursor.fetchone()
            if rr:
                lab_group_id = rr[0]
                self.cursor.execute("SELECT id, student_name FROM students WHERE group_id=?", (lab_group_id,))
                lab_ids_by_name = {n.lower(): i for i, n in self.cursor.fetchall()}

        # --- обход студентов текущей группы ---------------------------
        self.cursor.execute(
            "SELECT id, student_name, otrabotka, exam "
            "FROM students WHERE group_id=?", (group_id,))
        for sid, sname, o_val, ex_val in self.cursor.fetchall():

            otrabotka = o_val or 0.0
            exam      = ex_val or 0.0

            # «лента» оценок в *этой* группе (длина = все даты!)
            grades_here = get_grades_array(self.cursor, group_id, sid)

            # -----------------------------------------------------------
            #  A)------- Лабораторная группа
            # -----------------------------------------------------------
            if base_is_lab:
                cnt_n, ro, _, r_val = calc_lab_values(grades_here, otrabotka)
                otrabotka = reset_otrabotka_if_needed(self.cursor, sid, cnt_n, otrabotka)

                it_val = r_val
                let, dig = get_equivalents(it_val)
                self.cursor.execute("""
                    UPDATE students SET
                        letter_count       = ?,
                        ro_value           = ?,
                        r_value            = ?,
                        itog_value         = ?,
                        letter_equivalent  = ?,
                        digital_equivalent = ?
                    WHERE id=?""",
                    (cnt_n, ro, r_val, it_val, let, float(dig), sid))
                continue          # следующий студент

            # -----------------------------------------------------------
            #  B)------- Теоретическая группа
            # -----------------------------------------------------------
            if not include_theor:         # теорию отключили чек-боксом
                self.cursor.execute("""
                    UPDATE students SET
                        letter_count=0, ro_value=0,
                        r_value=0, itog_value=0,
                        letter_equivalent='F', digital_equivalent=0
                    WHERE id=?""", (sid,))
                continue

            # ---- статистика лабораторной пары (если подтягиваем) -----
            lab_stats = {'lab_count': 0, 'lab_numeric_sum': 0.0,
                         'lab_replaced_sum': 0.0}
            if include_labs and sname.lower() in lab_ids_by_name:
                lab_sid = lab_ids_by_name[sname.lower()]

                # --- берём ОТРabotка из строки ЛАБ-группы --------------  # FIX
                self.cursor.execute("SELECT COALESCE(otrabotka,0) FROM students WHERE id=?", (lab_sid,))
                lab_o_val = self.cursor.fetchone()[0] or 0.0              # FIX

                lab_grades = get_grades_array(self.cursor, lab_group_id, lab_sid)

                lab_stats['lab_count'] = len(lab_grades)
                for g in lab_grades:
                    try:
                        v = float(g)
                        lab_stats['lab_numeric_sum']  += v
                        lab_stats['lab_replaced_sum'] += v
                    except (TypeError, ValueError):
                        lab_stats['lab_replaced_sum'] += lab_o_val        # FIX

            # ---- расчёт показателей ----------------------------------
            cnt_n, ro, _, r_val, _, it_val, let, dig = calc_theory_lab_values(
                theory_grades = grades_here,
                manual_o      = otrabotka,
                exam          = exam,
                include_exam  = include_exam,
                lab_data      = lab_stats
            )
            otrabotka = reset_otrabotka_if_needed(self.cursor, sid, cnt_n, otrabotka)

            # ---- запись в БД -----------------------------------------
            self.cursor.execute("""
                UPDATE students SET
                    letter_count       = ?,
                    ro_value           = ?,
                    r_value            = ?,
                    itog_value         = ?,
                    letter_equivalent  = ?,
                    digital_equivalent = ?
                WHERE id=?""",
                (cnt_n, ro, r_val, it_val, let, float(dig), sid))

        self.conn.commit()
        self.append_log("Пересчёт завершён.")
        self.refresh_table()

    def recalc_whole_pair(self, theory_group_id: int):
        """
        Пересчитать показатели сразу у обеих таблиц:
        • у самой теоретической группы (theory_group_id)
        • у её зеркальной «_Лаб»-группы, если она существует.
        """
        # 1) базовая (теория)
        self._recalc_one_group(theory_group_id)

        # 2) зеркальная «…_Лаб»
        self.cursor.execute(
            "SELECT group_name FROM groups WHERE id=?", (theory_group_id,))
        row = self.cursor.fetchone()
        if not row:
            return
        base_name = row[0]
        lab_name = f"{base_name}_Лаб"

        self.cursor.execute(
            "SELECT id FROM groups WHERE group_name=?", (lab_name,))
        row_lab = self.cursor.fetchone()
        if row_lab:
            self._recalc_one_group(row_lab[0])


    # ─────────────────────────────────────────────────────────────
    #  Пересчёт ОДНОЙ группы (используется recalc_whole_pair)
    # ─────────────────────────────────────────────────────────────
    def _recalc_one_group(self, group_id: int):
        self.cursor.execute(
            "SELECT group_name, include_exam, include_labs, include_theory "
            "FROM groups WHERE id=?", (group_id,))
        row = self.cursor.fetchone()
        if not row:
            return

        gname, fl_exam, fl_labs, fl_theory = row
        base_is_lab   = gname.endswith("_Лаб")
        include_exam  = bool(fl_exam)
        include_labs  = bool(fl_labs) and not base_is_lab
        include_theor = bool(fl_theory) or base_is_lab

        # --- лабораторная пара (если нужна) ---------------------------
        lab_group_id = None
        lab_ids_by_name = {}
        if include_labs:
            lab_name = f"{gname}_Лаб"
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_name,))
            rr = self.cursor.fetchone()
            if rr:
                lab_group_id = rr[0]
                self.cursor.execute("SELECT id, student_name FROM students WHERE group_id=?", (lab_group_id,))
                lab_ids_by_name = {n.lower(): i for i, n in self.cursor.fetchall()}

        # --- обход студентов ------------------------------------------
        self.cursor.execute(
            "SELECT id, student_name, otrabotka, exam "
            "FROM students WHERE group_id=?", (group_id,))
        for sid, sname, o_val, ex_val in self.cursor.fetchall():

            otrabotka = o_val or 0.0
            exam      = ex_val or 0.0
            grades_here = get_grades_array(self.cursor, group_id, sid)

            if base_is_lab:
                cnt_n, ro, _, r_val = calc_lab_values(grades_here, otrabotka)
                otrabotka = reset_otrabotka_if_needed(self.cursor, sid, cnt_n, otrabotka)

                it_val = r_val
                let, dig = get_equivalents(it_val)
                self.cursor.execute("""
                    UPDATE students SET
                        letter_count       = ?,
                        ro_value           = ?,
                        r_value            = ?,
                        itog_value         = ?,
                        letter_equivalent  = ?,
                        digital_equivalent = ?
                    WHERE id=?""",
                    (cnt_n, ro, r_val, it_val, let, float(dig), sid))
                continue

            if not include_theor:
                self.cursor.execute("""
                    UPDATE students SET
                        letter_count=0, ro_value=0,
                        r_value=0, itog_value=0,
                        letter_equivalent='F', digital_equivalent=0
                    WHERE id=?""", (sid,))
                continue

            lab_stats = {'lab_count': 0, 'lab_numeric_sum': 0.0,
                         'lab_replaced_sum': 0.0}
            if include_labs and sname.lower() in lab_ids_by_name:
                lab_sid = lab_ids_by_name[sname.lower()]
                lab_grades = get_grades_array(self.cursor, lab_group_id, lab_sid)

                lab_stats['lab_count'] = len(lab_grades)
                for g in lab_grades:
                    try:
                        v = float(g)
                        lab_stats['lab_numeric_sum']  += v
                        lab_stats['lab_replaced_sum'] += v
                    except (TypeError, ValueError):
                        lab_stats['lab_replaced_sum'] += otrabotka

            cnt_n, ro, _, r_val, _, it_val, let, dig = calc_theory_lab_values(
                theory_grades = grades_here,
                manual_o      = otrabotka,
                exam          = exam,
                include_exam  = include_exam,
                lab_data      = lab_stats
            )
            otrabotka = reset_otrabotka_if_needed(self.cursor, sid, cnt_n, otrabotka)

            self.cursor.execute("""
                UPDATE students SET
                    letter_count       = ?,
                    ro_value           = ?,
                    r_value            = ?,
                    itog_value         = ?,
                    letter_equivalent  = ?,
                    digital_equivalent = ?
                WHERE id=?""",
                (cnt_n, ro, r_val, it_val, let, float(dig), sid))

        self.conn.commit()

    def get_lab_group_data(self, lab_group_id: int, manual_o: float):
        """
        lab_count        – ВСЕ даты в группе
        lab_numeric_sum  – сумма числовых оценок
        lab_replaced_sum – сумма, где «не число» заменено на manual_o
        """
        # ❶  общее число дат в лаб-группе
        self.cursor.execute("SELECT COUNT(*) FROM dates WHERE group_id=?", (lab_group_id,))
        total_dates = self.cursor.fetchone()[0] or 0

        lab_numeric_sum  = 0.0
        lab_replaced_sum = 0.0

        # ❷  проходим все оценки
        self.cursor.execute("""
            SELECT grade
              FROM grades g
              JOIN students s ON g.student_id = s.id
             WHERE s.group_id = ?
        """, (lab_group_id,))
        for (grade,) in self.cursor.fetchall():
            try:
                v = float(grade)
                lab_numeric_sum  += v
                lab_replaced_sum += v
            except (TypeError, ValueError):
                lab_replaced_sum += manual_o

        return {
            'lab_count':        total_dates,
            'lab_numeric_sum':  lab_numeric_sum,
            'lab_replaced_sum': lab_replaced_sum
        }

    # ------------------ ЭКСПОРТ / ИМПОРТ И Т.Д. ------------------
    def export_to_excel(self):
        msg_box = QMessageBox(self)
        msg_box.setWindowTitle("Экспорт")
        msg_box.setText("Экспортировать только текущую группу или все?")
        btn_curr = msg_box.addButton("Текущая группа", QMessageBox.AcceptRole)
        btn_all = msg_box.addButton("Все группы", QMessageBox.AcceptRole)
        btn_cancel = msg_box.addButton("Отмена", QMessageBox.RejectRole)
        msg_box.exec_()
        if msg_box.clickedButton() == btn_cancel:
            self.append_log("Экспорт отменён.")
            return
        elif msg_box.clickedButton() == btn_curr:
            gname = self.group_combo.currentText().strip()
            if not gname:
                QMessageBox.warning(self, "Ошибка", "Нет выбранной группы.")
                return
            groups = [gname]
        else:
            self.cursor.execute("SELECT group_name FROM groups")
            all_g = self.cursor.fetchall()
            if not all_g:
                QMessageBox.warning(self, "Ошибка", "Нет групп для экспорта.")
                return
            groups = [x[0] for x in all_g]
        from openpyxl import Workbook
        wb = Workbook()
        def_sheet = wb.active
        wb.remove(def_sheet)
        for grp in groups:
            # Узнаём тип
            self.cursor.execute("SELECT id, group_type FROM groups WHERE group_name=?", (grp,))
            row_g = self.cursor.fetchone()
            if not row_g:
                continue
            group_id, gtype = row_g
    
            # Если gtype == 'lab', то лист = f"{grp} (Лаб)"
            # Иначе лист = grp
            if gtype == "lab":
                sheet_title = f"{grp} (Лаб)"
            else:
                sheet_title = grp
            ws = wb.create_sheet(title=sheet_title)
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (grp,))
            row_g = self.cursor.fetchone()
            if not row_g:
                continue
            group_id = row_g[0]
            self.cursor.execute("SELECT id, date_label FROM dates WHERE group_id=?", (group_id,))
            dd_rows = self.cursor.fetchall()
            dd_rows.sort(key=lambda x: self.date_sort_key(x[1]))
            if self.include_exam:
                self.student_fields = ["letter_count", "ro_value", "otrabotka", "r_value", "exam", "itog_value"]
            else:
                self.student_fields = ["letter_count", "ro_value", "otrabotka", "r_value", "itog_value"]
            special_headers = ["Н", "РО", "Отработка", "Р", "Экзам", "Итог"]
            col_headers = ["Студент"] + [x[1] for x in dd_rows] + special_headers + ["Циф. экв.", "Бук. экв."]

            ws.append(col_headers)
            self.cursor.execute(
                "SELECT id, student_name, letter_count, ro_value, otrabotka, r_value, exam, itog_value, digital_equivalent, letter_equivalent FROM students WHERE group_id=?",
                (group_id,)
            )
            st_data = self.cursor.fetchall()
            st_data.sort(key=lambda x: x[1].lower())
            for st_ in st_data:
                sname = st_[1]
                letc = st_[2] or 0
                rovl = st_[3] or 0
                otrb = st_[4] or 0
                rv = st_[5] or 0
                exv = st_[6] or 0
                itv = st_[7] or 0
                digital_val = f"{st_[8]:.2f}" if st_[8] is not None else "0.00"
                letter_val = st_[9] if st_[9] is not None else "F"
                row_xl = [sname]
                for (did, dlab) in dd_rows:
                    self.cursor.execute("SELECT grade FROM grades WHERE student_id=? AND date_id=?", (st_[0], did))
                    row_gr = self.cursor.fetchone()
                    val_gr = row_gr[0] if row_gr else ""
                    row_xl.append(val_gr)
                row_xl += [str(letc), f"{rovl:.2f}", f"{otrb:.2f}", f"{rv:.2f}", f"{exv:.2f}", f"{itv:.2f}", digital_val, letter_val]
                ws.append(row_xl)
        fname, _ = QFileDialog.getSaveFileName(self, "Сохранить Excel", "export.xlsx", "Excel Files (*.xlsx)")
        if not fname:
            return
        wb.save(fname)
        self.append_log(f"Экспорт в '{fname}' завершён.")
        QMessageBox.information(self, "Экспорт", f"Данные экспортированы в '{fname}'")
    
    def import_from_excel(self):
        fname, _ = QFileDialog.getOpenFileName(self, "Импорт Excel", "", "Excel Files (*.xlsx *.xls)")
        if not fname:
            return
        try:
            import openpyxl
            # data_only=True возвращает результат формул, а не сами формулы
            wb = openpyxl.load_workbook(fname, data_only=True)
        except Exception as e:
            QMessageBox.warning(self, "Ошибка", f"Не удалось открыть файл:\n{e}")
            return
    
        def cell_value_to_str(cell_val):
            """Преобразует ячейку в строку (с уrespectом чисел)."""
            if isinstance(cell_val, (int, float)):
                if isinstance(cell_val, float):
                    if cell_val.is_integer():
                        return str(int(cell_val))
                    else:
                        return f"{cell_val:.2f}"
                return str(cell_val)
            if cell_val is None:
                return ""
            return str(cell_val).strip()
    
        # Обходим все листы книги
        for sheet in wb.worksheets:
            sheet_name = sheet.title.strip()
    
            # Определяем тип: если лист оканчивается на "(Лаб)", считаем lab, иначе classic
            is_lab = False
            if sheet_name.endswith("(Лаб)"):
                is_lab = True
                base_name = sheet_name.replace("(Лаб)", "").strip()
                actual_group_name = base_name
            else:
                actual_group_name = sheet_name
    
            # Загружаем строки листа
            rows = list(sheet.iter_rows(min_row=1, values_only=True))
    
            # В любом случае, сначала создаём (или находим) группу
            self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (actual_group_name,))
            row_g = self.cursor.fetchone()
            if not row_g:
                grp_type = "lab" if is_lab else "classic"
                self.cursor.execute(
                    "INSERT INTO groups(group_name, group_type) VALUES(?, ?)",
                    (actual_group_name, grp_type)
                )
                self.conn.commit()
                self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (actual_group_name,))
                row_g = self.cursor.fetchone()
    
            if not row_g:
                # Если почему-то не удалось создать/найти
                self.append_log(f"Не удалось создать/найти группу '{actual_group_name}'. Пропускаем лист '{sheet_name}'.")
                continue
            
            group_id = row_g[0]
    
            # Если вообще нет строк (или 0 строк), тогда у нас просто будет пустая группа
            if not rows:
                self.append_log(f"Лист '{sheet_name}' пустой, но группа '{actual_group_name}' создана/существует без студентов.")
                continue
            
            # Если есть хотя бы одна строка (скорее всего заголовок)
            headers = [cell_value_to_str(cell) for cell in rows[0]]
            if not headers:
                self.append_log(f"Лист '{sheet_name}' содержит данные, но нет заголовков. Пропускаем обработку студентов.")
                continue
            
            # Проверяем, что первый заголовок (индекс=0) – "Студент" / "Students" / ...
            # Если нет, то тоже не добавляем студентов (но группа уже есть)
            first_header = headers[0].strip().lower()
            if first_header not in ["студент", "students", "студенты"]:
                self.append_log(f"Лист '{sheet_name}': первый столбец не 'Студент'. Пропускаем добавление студентов.")
                continue
            
            # Теперь разбираем остальные заголовки
            rev_map = {v.lower(): k for k,v in class_names_rus.items()}
            date_headers = []   # (idx, заголовок)
            field_headers = []  # (idx, имя_поля_в_БД)
    
            for idx, header in enumerate(headers):
                if idx == 0:
                    continue  # Первая колонка – имя студента
                header_norm = header.strip()
                if header_norm.lower() in rev_map:
                    field_headers.append((idx, rev_map[header_norm.lower()]))
                else:
                    date_headers.append((idx, header_norm))
    
            # Вставляем даты в БД (если их ещё нет)
            for idx, d_lab in date_headers:
                d_lab_str = d_lab.strip()
                if d_lab_str:
                    self.cursor.execute(
                        "SELECT 1 FROM dates WHERE group_id=? AND TRIM(date_label)=?",
                        (group_id, d_lab_str)
                    )
                    if not self.cursor.fetchone():
                        self.cursor.execute("INSERT INTO dates(group_id, date_label) VALUES(?,?)", (group_id, d_lab_str))
            self.conn.commit()
    
            # Сопоставляем date_label -> date_id
            self.cursor.execute("SELECT id, date_label FROM dates WHERE group_id=?", (group_id,))
            dd_rows = self.cursor.fetchall()
            label_to_id = {str(dr[1]).strip().lower(): dr[0] for dr in dd_rows}
    
            # Перебираем все строки, начиная со 2-ой (индекс=1), т.к. 1-ая была заголовком
            for data_row in rows[1:]:
                if not data_row:
                    continue
                row_values = [cell_value_to_str(cell) for cell in data_row]
                if not row_values:
                    continue
                
                sname = row_values[0].strip()
                if not sname:
                    continue
                
                # Ищем/добавляем студента
                self.cursor.execute(
                    "SELECT id FROM students WHERE group_id=? AND lower(student_name)=lower(?)",
                    (group_id, sname)
                )
                row_s = self.cursor.fetchone()
                if not row_s:
                    # Добавляем
                    self.cursor.execute(
                        """INSERT INTO students 
                           (group_id, student_name, ro_value, itog_value, otrabotka, exam, letter_count, r_value)
                           VALUES(?,?,?,?,?,?,?,?)""",
                        (group_id, sname, 0,0,0,0,0,0)
                    )
                    self.conn.commit()
                    self.cursor.execute(
                        "SELECT id FROM students WHERE group_id=? AND lower(student_name)=lower(?)",
                        (group_id, sname)
                    )
                    row_s = self.cursor.fetchone()
    
                if not row_s:
                    continue  # Не удалось добавить/получить ID
                
                sid = row_s[0]
    
                # Обновляем специальные поля (letter_count, ro_value, ...)
                for (col_idx, db_field) in field_headers:
                    val_str = row_values[col_idx] if col_idx < len(row_values) else ""
                    if db_field == "letter_count":
                        try:
                            i_val = int(float(val_str))
                        except:
                            i_val = 0
                        self.cursor.execute(f"UPDATE students SET letter_count=? WHERE id=?", (i_val, sid))
                    else:
                        try:
                            ff = float(val_str)
                        except:
                            ff = 0.0
                        self.cursor.execute(f"UPDATE students SET {db_field}=? WHERE id=?", (ff, sid))
    
                # Обновляем оценки (date_headers)
                for (col_idx, d_lab_raw) in date_headers:
                    d_lab_norm = d_lab_raw.strip().lower()
                    if d_lab_norm not in label_to_id:
                        continue
                    d_id = label_to_id[d_lab_norm]
                    val_str = row_values[col_idx] if col_idx < len(row_values) else ""
                    if val_str:
                        try:
                            ff = float(val_str)
                            if ff > 100:
                                val_str = "100"
                        except:
                            pass
                    # Ищем оценку
                    self.cursor.execute(
                        "SELECT id FROM grades WHERE student_id=? AND date_id=?",
                        (sid, d_id)
                    )
                    row_gr = self.cursor.fetchone()
                    if row_gr:
                        self.cursor.execute("UPDATE grades SET grade=? WHERE id=?", (val_str, row_gr[0]))
                    else:
                        self.cursor.execute("INSERT INTO grades(student_id, date_id, grade) VALUES(?,?,?)",
                                            (sid, d_id, val_str))
    
            self.conn.commit()
    
        # После обхода всех листов
        self.load_groups()
        if self.group_combo.count() > 0:
            self.group_combo.setCurrentIndex(0)
        self.refresh_table()
        self.append_log(f"Импорт из '{fname}' завершён.")
        QMessageBox.information(self, "Импорт", f"Импорт из '{fname}' завершён.")

    def on_row_header_context_menu(self, pos):
        pass

    def backup_data(self):
        fname, _ = QFileDialog.getSaveFileName(self, "Сохранить резервную копию", "", "SQLite DB (*.db)")
        if not fname:
            self.append_log("Резервное копирование отменено.")
            return
        try:
            self.conn.commit()
            backup_conn = sqlite3.connect(fname)
            self.conn.backup(backup_conn)
            backup_conn.close()
            self.append_log(f"Резервная копия сохранена в {fname}")
            QMessageBox.information(self, "Резервная копия", f"Резервная копия сохранена в {fname}")
        except Exception as e:
            QMessageBox.warning(self, "Ошибка", f"Не удалось создать резервную копию:\n{e}")
    
    def restore_data(self):
        backup_file, _ = QFileDialog.getOpenFileName(self, "Выбрать резервную копию", "", "SQLite DB (*.db)")
        if not backup_file:
            self.append_log("Восстановление отменено.")
            return
        ans = QMessageBox.question(self, "Восстановление", "При восстановлении текущие данные будут потеряны. Продолжить?",
                                   QMessageBox.Yes | QMessageBox.No, QMessageBox.No)
        if ans != QMessageBox.Yes:
            return
        try:
            self.conn.close()
            os.remove(DB_NAME)
            from shutil import copyfile
            copyfile(backup_file, DB_NAME)
            self.conn = sqlite3.connect(DB_NAME)
            self.cursor = self.conn.cursor()
            self.init_db()
            self.load_groups()
            self.refresh_table()
            self.append_log("Данные успешно восстановлены.")
            QMessageBox.information(self, "Восстановление", "Данные успешно восстановлены.")
        except Exception as e:
            QMessageBox.warning(self, "Ошибка", f"Не удалось восстановить данные:\n{e}")
    
    # ------------------ RUPY ------------------
    def open_rupy(self):
        win = RupyWindow(self)
        win.exec_()
    
    # ------------------ ГЛОБАЛЬНЫЙ ПОИСК ------------------
    def open_global_search(self):
        query = self.global_search_line_edit.text().strip()
        if not query:
            QMessageBox.information(self, "Информация", "Введите запрос для глобального поиска.")
            return
        dlg = GlobalSearchDialog(self.cursor.connection, query, self)
        dlg.exec_()
    
    # ------------------ КОНТЕКСТНЫЕ МЕНЮ ------------------
    def on_col_header_context_menu(self, pos):
        col = self.table.horizontalHeader().logicalIndexAt(pos)
        if col < 0:
            return
        if col == 0:  # "Студент"
            return
        d_count = len(self.date_columns)
        if 1 <= col < 1 + d_count:
            date_idx = col - 1
            did, dlab, dnotes = self.date_columns[date_idx]
            menu = QMenu(self)
            act_del = menu.addAction(f"Удалить дату '{dlab}'")
            act_del.triggered.connect(lambda: self.delete_date(did, dlab))
            
            act_note = menu.addAction("Изменить примечание")
            act_note.triggered.connect(lambda: self.edit_date_note(did))
            
            menu.exec_(self.table.horizontalHeader().mapToGlobal(pos))
    
    def on_lab_col_header_context_menu(self, pos):
        col = self.lab_table.horizontalHeader().logicalIndexAt(pos)
        # 0 = «Студент», далее — даты
        if col <= 0 or col > len(self.date_columns_lab):
            return
        did, dlabel, _ = self.date_columns_lab[col-1]
        menu = QMenu(self)
        act_del  = menu.addAction(f"Удалить дату «{dlabel}»")
        act_note = menu.addAction("Изменить примечание")
        action = menu.exec_(self.lab_table.horizontalHeader().mapToGlobal(pos))
        if action == act_del:
            self.delete_date(did, dlabel)   # удалит только эту запись для Лаб-группы
        elif action == act_note:
            self.edit_date_note(did)        # поменяет note именно для Лаб-даты

    def edit_date_note(self, date_id):
        self.cursor.execute("SELECT date_label, COALESCE(notes, '') FROM dates WHERE id=?", (date_id,))
        row_d = self.cursor.fetchone()
        if not row_d:
            return
        d_label, d_notes = row_d
        new_note, ok = QInputDialog.getMultiLineText(
            self, "Примечание к дате",
            f"Примечание для «{d_label}»:", d_notes
        )
        if ok:
            self.cursor.execute("UPDATE dates SET notes=? WHERE id=?", (new_note, date_id))
            self.conn.commit()
            self.append_log(f"Примечание обновлено: {d_label}")
            self.refresh_table()
    
    def on_table_context_menu(self, pos):
        item = self.table.itemAt(pos)
        if item and item.column() == 0:
            stud_name = item.text()
            menu = QMenu(self)
            act_del = menu.addAction(f"Удалить студента '{stud_name}'")
            act_del.triggered.connect(lambda: self.delete_student(stud_name))
            menu.exec_(self.table.viewport().mapToGlobal(pos))
    
    def delete_student(self, student_name):
        gname = self.group_combo.currentText().strip()
        if not gname:
            return
        
        self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (gname,))
        row_g = self.cursor.fetchone()
        if not row_g:
            return
        group_id = row_g[0]
    
        ans = QMessageBox.question(self, "Удаление студента", f"Удалить '{student_name}'?", QMessageBox.Yes | QMessageBox.No)
        if ans == QMessageBox.Yes:
            # Удаляем из текущей группы
            self.cursor.execute(
                "SELECT id FROM students WHERE group_id=? AND student_name=?",
                (group_id, student_name)
            )
            row_s = self.cursor.fetchone()
            if not row_s:
                return
            sid = row_s[0]
            self.cursor.execute("DELETE FROM grades WHERE student_id=?", (sid,))
            self.cursor.execute("DELETE FROM students WHERE id=?", (sid,))
            self.conn.commit()
            self.append_log(f"Студент '{student_name}' удалён из {gname}")
            self.refresh_table()
    
            # Синхронизируем
            parallel_gname = get_parallel_group_name(gname)
            if parallel_gname and parallel_gname != gname:
                self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (parallel_gname,))
                row_p = self.cursor.fetchone()
                if row_p:
                    p_group_id = row_p[0]
                    self.cursor.execute(
                        "SELECT id FROM students WHERE group_id=? AND student_name=?",
                        (p_group_id, student_name)
                    )
                    row_sp = self.cursor.fetchone()
                    if row_sp:
                        sid_p = row_sp[0]
                        self.cursor.execute("DELETE FROM grades WHERE student_id=?", (sid_p,))
                        self.cursor.execute("DELETE FROM students WHERE id=?", (sid_p,))
                        self.conn.commit()
                        self.append_log(f"(Синхронизировано) Студент '{student_name}' удалён из {parallel_gname}")
                        self.refresh_table()

    
    def delete_date(self, date_id, date_lbl):
        self.cursor.execute("DELETE FROM grades WHERE date_id=?", (date_id,))
        self.cursor.execute("DELETE FROM dates WHERE id=?", (date_id,))
        self.conn.commit()
        self.append_log(f"Дата '{date_lbl}' удалена.")
        self.refresh_table()
    
    # ------------------ РАЗМЕР КОЛОНОК ------------------
    def on_section_resized(self, index, old_size, new_size):
        self.user_column_widths[index] = new_size
    
    # ------------------ ЗАКРЫТИЕ ОКНА ------------------
    def closeEvent(self, event):
        self.conn.close()
        event.accept()

    # ─────────────────────────────────────────────────────────────
    #  Обработчик изменений в лабораторной таблице
    # ─────────────────────────────────────────────────────────────
    def on_lab_item_changed(self, item: QTableWidgetItem):
        """
        Обработка изменений в лабораторной таблице.
        • Числовые клетки/«Отработка» — не-число → 0, >100 → 100.
        """
        if self.ignore_changes:
            return
    
        row, col   = item.row(), item.column()
        new_val_in = item.text().strip()
    
        # ---- id студента ----------------------------------------------
        sid_item = self.lab_table.item(row, 0)
        if not sid_item:
            return
        sid = sid_item.data(Qt.UserRole)
    
        # ---- id и сервисная инфа по группе -----------------------------
        cur_group = self.group_combo.currentText().strip()
        lab_gname = cur_group if cur_group.endswith('_Лаб') else f"{cur_group}_Лаб"
        self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (lab_gname,))
        grp_row = self.cursor.fetchone()
        if not grp_row:
            return
        lab_group_id = grp_row[0]
    
        date_cnt = len(self.date_columns_lab)
        idx_otr  = date_cnt + 3     # позиция столбца «O»
    
        # ===== 1.  Оценка за конкретную лабораторную дату ==============
        if 1 <= col <= date_cnt:
            date_id = self.date_columns_lab[col-1][0]
            try:
                val = float(new_val_in.replace(',', '.'))
                if val > 100:
                    val = 100
            except ValueError:
                val = 'Н' if new_val_in.upper() == 'Н' else ""
    
            val_str = str(int(val)) if isinstance(val, float) and val.is_integer() else str(val)
    
            self.cursor.execute("SELECT id FROM grades WHERE student_id=? AND date_id=?", (sid, date_id))
            r = self.cursor.fetchone()
            if r:
                self.cursor.execute("UPDATE grades SET grade=? WHERE id=?", (val_str, r[0]))
            else:
                self.cursor.execute("INSERT INTO grades(student_id, date_id, grade) VALUES(?,?,?)",
                                    (sid, date_id, val_str))
    
            if val_str != new_val_in:
                self.ignore_changes = True
                item.setText(val_str)
                self.ignore_changes = False
    
        # ===== 2.  Колонка «Отработка» =================================
        elif col == idx_otr:
            # «Н» в строке — в первой спец-колонке после дат
            n_item = self.lab_table.item(row, 1 + date_cnt)
            try:
                n_val = float(n_item.text()) if n_item else 0
            except ValueError:
                n_val = 0
    
            # если Н = 0, отработку ставить нельзя
            if n_val == 0:
                self.ignore_changes = True
                item.setText("0")
                self.ignore_changes = False
                return
    
            try:
                o_val = float(new_val_in.replace(',', '.'))
            except ValueError:
                o_val = 0.0
            if o_val > 100:
                o_val = 100.0
    
            fixed_text = f"{o_val:.0f}" if o_val.is_integer() else f"{o_val:.2f}"
            if fixed_text != new_val_in:
                self.ignore_changes = True
                item.setText(fixed_text)
                self.ignore_changes = False
    
            self.cursor.execute("UPDATE students SET otrabotka=? WHERE id=?", (o_val, sid))
    
        else:
            # прочие колонки в Лаб-таблице не редактируются
            return
    
        # ---- фиксация и пересчёт пары ----------------------------------
        self.conn.commit()
    
        base_gname = lab_gname[:-4] if lab_gname.endswith('_Лаб') else lab_gname
        self.cursor.execute("SELECT id FROM groups WHERE group_name=?", (base_gname,))
        base_row = self.cursor.fetchone()
        if base_row:
            self.recalc_whole_pair(base_row[0])
    
        self.refresh_table()

# ------------------ Точка входа ------------------
def main():
    app = QApplication(sys.argv)
    # Свойства по умолчанию
    app.setStyle(QStyleFactory.create("Fusion"))
    app.setWindowIcon(QIcon(get_image_path("app_logo.png")))
    app.setProperty("disable_colors", False)
    w = JournalApp()
    w.show()
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()