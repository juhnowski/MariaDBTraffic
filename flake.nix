{
  description = "Стенд для сбора сырых 16КБ блоков данных MariaDB (InnoDB)";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      
      pythonEnv = pkgs.python3.withPackages (ps: [
        ps.mysql-connector
      ]);
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.cargo
          pkgs.rustc
          pkgs.mariadb
          pythonEnv
        ];

        shellHook = ''
          export MDB_DIR="$PWD/mariadb_data"
          export MDB_SOCKET="$MDB_DIR/mysql.sock"
          export MDB_PID="$MDB_DIR/mysql.pid"
          export MDB_CONF="$MDB_DIR/my.cnf"
          export MDB_LOG="$MDB_DIR/mysql.log"
          
          mkdir -p "$MDB_DIR"

          # Генерируем локальную конфигурацию my.cnf
          if [ ! -f "$MDB_CONF" ]; then
            echo "[Nix] Создание локальной конфигурации MariaDB..."
            # Используем \$USER, чтобы имя пользователя подставлялось в рантайме bash
            cat <<EOF > "$MDB_CONF"
[mysqld]
user = \$USER
datadir = $MDB_DIR
socket = $MDB_SOCKET
pid-file = $MDB_PID
port = 3306
bind-address = 127.0.0.1
log-error = $MDB_LOG

# Настройки InnoDB под сбор сырых страниц
innodb_file_per_table = 1
innodb_buffer_pool_size = 64M
innodb_flush_log_at_trx_commit = 1
innodb_doublewrite = 0
innodb_stats_on_metadata = 0
EOF

            echo "[Nix] Инициализация системных таблиц MariaDB..."
            mariadb-install-db --datadir="$MDB_DIR" --auth-root-authentication-method=normal > /dev/null
          fi

          echo "--------------------------------------------------------"
          echo " Доступные команды MariaDB-стенда:"
          echo "   start-mdb  - Запустить локальный сервер MariaDB"
          echo "   stop-mdb   - Остановить сервер MariaDB"
          echo "   run-bench  - Сгенерировать данные и собрать blocks (.ibd)"
          echo "   run-entropy - Вычислить энтропию"
          echo "--------------------------------------------------------"

          alias start-mdb="mariadbd --defaults-file=\$MDB_CONF > \$MDB_LOG 2>&1 &"
          alias stop-mdb="mariadb-admin --socket=\$MDB_SOCKET -u root shutdown"
          alias run-bench="python collect_mariadb_blocks.py"
          alias run-entropy="cargo run --release --manifest-path=$PWD/entropy_analyzer/Cargo.toml --"
        '';
      };
    };
}
