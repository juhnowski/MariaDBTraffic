{
  description = "Стенд для сбора сырых 16КБ блоков данных MariaDB (InnoDB)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux"; # Измените на aarch64-linux / x86_64-darwin, если у вас другая платформа
      pkgs = import nixpkgs { inherit system; };
      
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.mysql-connector-python # Официальный драйвер для работы с MariaDB/MySQL
      ]);
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.mariadb
          pythonEnv
        ];

        shellHook = ''
          export MDB_DIR="$PWD/mariadb_data"
          export MDB_SOCKET="$MDB_DIR/mysql.sock"
          export MDB_PID="$MDB_DIR/mysql.pid"
          export MDB_CONF="$MDB_DIR/my.cnf"
          
          mkdir -p "$MDB_DIR"

          # Генерируем локальную конфигурацию my.cnf
          if [ ! -f "$MDB_CONF" ]; then
            echo "[Nix] Создание локальной конфигурации MariaDB..."
            cat <<EOF > "$MDB_CONF"
[mysqld]
database = demo
user = ${builtins.getEnv "USER"}
datadir = $MDB_DIR
socket = $MDB_SOCKET
pid-file = $MDB_PID
port = 3306
bind-address = 127.0.0.1

# Настройки InnoDB под сбор сырых страниц
innodb_file_per_table = 1          # Каждая таблица в своем .ibd файле
innodb_buffer_pool_size = 64M      # Небольшой буфер для быстрого вытеснения на диск
innodb_flush_log_at_trx_commit = 1 # Сброс логов при каждом коммите
innodb_doublewrite = 0             # Отключаем doublewrite, чтобы не дублировать блоки в системном пространстве
innodb_stats_on_metadata = 0
EOF

            echo "[Nix] Инициализация системных таблиц MariaDB..."
            mariadb-install-db --datadir="$MDB_DIR" --auth-root-authentication-method=normal > /dev/null
          fi

          echo "--------------------------------------------------------"
          echo " Доступные команды MariaDB-стенда:"
          echo "   start-mdb  - Запустить локальный сервер MariaDB"
          echo "   stop-mdb   - Остановить сервер MariaDB"
          echo "   run-bench  - Сгенерировать данные и собрать блоки (.ibd)"
          echo "--------------------------------------------------------"

          alias start-mdb="mariadbd --defaults-file=\$MDB_CONF --daemonize"
          alias stop-mdb="mariadb-admin --socket=\$MDB_SOCKET -u root shutdown"
          alias run-bench="python collect_mariadb_blocks.py"
        '';
      };
    };
}
