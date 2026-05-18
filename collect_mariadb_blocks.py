import os
import shutil
import mysql.connector

OUTPUT_DIR = "./mariadb_bench_blocks"
MDB_DATA_DIR = "./mariadb_data/demo" # Путь к файлам нашей тестовой базы 'demo'

DB_CONFIG = {
    "user": "root",
    "host": "127.0.0.1",
    "port": 3306
}

SCENARIOS = {
    "1_duplicates": {
        "schema": """
            CREATE TABLE test_duplicates (
                id INT AUTO_INCREMENT PRIMARY KEY,
                payload TEXT
            ) ENGINE=InnoDB;
        """,
        "insert": """
            INSERT INTO test_duplicates (payload)
            VALUES (%s);
        """,
        "data_gen": lambda: [
            ("КОНСТАНТНЫЙ_ТЕКСТ_ДЛЯ_ПРОВЕРКИ_ДЕДУПЛИКАЦИИ_ВАРИАНТ_М_М_М_М_М_М_М",) 
            if i % 2 == 0 else 
            ("ДРУГОЙ_ШАБЛОННЫЙ_БЛОК_ДАННЫХ_МИН_МАКС_М_М_М_М_М_М_М_М_М_М_М_М_М",)
            for i in range(40000)
        ]
    },
    "2_updates": {
        "schema": """
            CREATE TABLE test_updates (
                id INT PRIMARY KEY,
                counter INT,
                updated_at TIMESTAMP
            ) ENGINE=InnoDB;
        """,
        "insert": """
            INSERT INTO test_updates (id, counter, updated_at) VALUES (%s, 0, NOW());
        """,
        "data_gen": lambda: [(i,) for i in range(10000)],
        "post_op": lambda cursor: [
            cursor.execute("UPDATE test_updates SET counter = counter + 1, updated_at = NOW() WHERE id % 2 = 0;"),
            cursor.execute("UPDATE test_updates SET counter = counter + 5, updated_at = NOW() WHERE id % 3 = 0;")
        ]
    },
    "3_denormalized": {
        "schema": """
            CREATE TABLE test_denormalized (
                id INT AUTO_INCREMENT PRIMARY KEY,
                region VARCHAR(100),
                manager VARCHAR(100),
                amount DECIMAL(10,2)
            ) ENGINE=InnoDB;
        """,
        "insert": """
            INSERT INTO test_denormalized (region, manager, amount) VALUES (%s, %s, %s);
        """,
        "data_gen": lambda: [
            (["Москва", "СПб", "Сибирь"][i % 3], ["Иванов И.И.", "Петров П.П."][i % 2], 100.50 * (i % 10))
            for i in range(30000)
        ]
    },
    "4_json": {
        "schema": """
            CREATE TABLE test_json (
                id INT AUTO_INCREMENT PRIMARY KEY,
                metadata JSON
            ) ENGINE=InnoDB;
        """,
        "insert": """
            INSERT INTO test_json (metadata) VALUES (%s);
        """,
        "data_gen": lambda: [
            (f'{{"user_id": {i}, "status": "active", "padding": "{ "A" * 2000 }"}}',)
            for i in range(3000)
        ]
    },
    "5_binary": {
        "schema": """
            CREATE TABLE test_binary (
                id INT AUTO_INCREMENT PRIMARY KEY,
                file_data LONGBLOB
            ) ENGINE=InnoDB;
        """,
        "insert": """
            INSERT INTO test_binary (file_data) VALUES (%s);
        """,
        "data_gen": lambda: [(os.urandom(16000),) for _ in range(500)]
    }
}

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    conn = mysql.connector.connect(**DB_CONFIG)
    cursor = conn.cursor()
    
    # Создаем тестовую базу данных
    cursor.execute("CREATE DATABASE IF NOT EXISTS demo;")
    cursor.execute("USE demo;")
    
    for name, config in SCENARIOS.items():
        print(f"\n--- Сценарий: {name} ---")
        table_name = f"test_{name.split('_', 1)[1]}"
        
        cursor.execute(f"DROP TABLE IF EXISTS {table_name};")
        cursor.execute(config["schema"])
        
        # Массовая вставка данных
        print(f"    Вставка записей...")
        rows = config["data_gen"]()
        cursor.executemany(config["insert"], rows)
        conn.commit()
        
        # Если сценарий требует дополнительных апдейтов (эффект MVCC для InnoDB)
        if "post_op" in config:
            print(f"    Выполнение модификации данных (UPDATE)...")
            config["post_op"](cursor)
            conn.commit()
            
        # Принудительно заставляем InnoDB закрыть таблицу и выгрузить страницы из Buffer Pool на диск
        print(f"    Сброс 16КБ страниц на диск (FLUSH)...")
        cursor.execute(f"FLUSH TABLES {table_name} FOR EXPORT;")
        
        # Копируем .ibd файл пока таблица заблокирована инструкцией FOR EXPORT
        src_file = os.path.join(MDB_DATA_DIR, f"{table_name}.ibd")
        dest_file = os.path.join(OUTPUT_DIR, f"mariadb_{name}.ibd.raw")
        
        if os.path.exists(src_file):
            shutil.copy(src_file, dest_file)
            size_kb = os.path.getsize(dest_file) // 1024
            print(f"    Сохранено: {dest_file} ({size_kb} KB, {size_kb // 16} блоков InnoDB)")
        else:
            print(f"    Ошибка: Файл {table_name}.ibd не найден!")
            
        # Освобождаем блокировку таблицы
        cursor.execute("UNLOCK TABLES;")

    cursor.close()
    conn.close()
    print("\n[+] Сбор данных для MariaDB успешно завершен!")

if __name__ == "__main__":
    main()
