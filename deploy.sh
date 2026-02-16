#!/bin/bash
set -e

# SCRIPT DÉPLOIEMENT GUACAMOLE 1.6.0


# 0. VARIABLE CONFIGURATION
DB_PASS="DH724JKLX?/C"
BASE_DIR="/opt/guacamole"

# 1. DEPENDANCES SYSTÈME
echo "[++++] Mise à jour du système et installation des outils... [++++]"
apt-get update -y && apt-get upgrade -y
apt-get install -y sudo curl wget zip unzip nano ca-certificates gnupg lsb-release

# 2. INSTALLATION DOCKER
echo "[*] Installation de Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    apt-get install -y docker-compose-plugin > /dev/null 2>&1
fi

# 3. PRÉPARATION FICHIERS ET DOSSIERS
echo "[++++] Creation des dossiers... [++++]"
mkdir -p "$BASE_DIR"/{postgres,recordings,drive,extensions}
mkdir -p "$BASE_DIR"/branding-build/{guacamole-branding/resources,guacamole-branding/META-INF}

# 3.1 AJOUT PERMISSION POUR ENREGISTREMENT ---
chown -R 1000:1001 /opt/guacamole/recordings
chmod -R 770 /opt/guacamole/recordings
chmod g+s /opt/guacamole/recordings
cd "$BASE_DIR"

# Init DB si le fichier n'existe pas
if [ ! -f initdb.sql ]; then
    echo "[++++] Generation du script SQL initial... [++++]"
    docker run --rm guacamole/guacamole:1.6.0 /opt/guacamole/bin/initdb.sh --postgresql > initdb.sql
fi

#     CRÉATION DU BRANDING EXTENSION

echo "[++++] Creation du Branding (Logo & Messages)... [++++]"

BUILD_DIR="$BASE_DIR/branding-build/guacamole-branding"

# 1. Le message d'enregistrement
cat  > "$BUILD_DIR/guac-manifest.json" <<EOF
{
    "guacamoleVersion": "*",
    "name": "Custom Branding",
    "namespace": "custom-branding-extension",
    "translations": [
        "resources/en.json",
        "resources/fr.json"
    ],
    "css": [
        "resources/branding.css"
    ]
}
EOF

# 2. Le CSS (Avertissement enregistrement de session)
cat > "$BUILD_DIR/resources/branding.css" <<EOF
/* Ajout Message Avertissement sous la boite de login */
.login-ui .login-dialog::after {
    content: "LES SESSIONS SONT ENREGISTRÉES";
    display: block;
    text-align: center;
    color: #e74c3c;
    font-weight: bold;
    margin-top: 15px;
    font-size: 0.9em;
    padding: 10px;
    background: rgba(0,0,0,0.05);
    border-radius: 4px;
}
EOF

# 3. Fichier de langue (Overlay Textes standards)
cat > "$BUILD_DIR/resources/fr.json" <<EOF
{
    "APP": {
        "NAME": " **TEST** GUACAMOLE CH MARCHANT"
    },
    "LOGIN": {
        "INFO_WELCOME": "Veuillez vous identifier. Toutes les actions sont enregistrées."
    }
}
EOF
# Copie en anglais pour être sûr
cp "$BUILD_DIR/resources/fr.json" "$BUILD_DIR/resources/en.json"


# 4. Compilation du .JAR 
echo "[++++] Compilation de l'extension Branding... [++++]"

cd "$BUILD_DIR"
zip -r "$BASE_DIR/extensions/branding.jar" .

cd "$BASE_DIR"
# Nettoyage build
rm -rf "$BASE_DIR/branding-build"

# Ajout de guacamole-history-recording-storage-1.6.0
cd extensions/
wget https://archive.apache.org/dist/guacamole/1.6.0/binary/guacamole-history-recording-storage-1.6.0.tar.gz ; tar -vxf guacamole-history-recording-storage-1.6.0.tar.gz  ; cd guacamole-history-recording-storage-1.6.0 ; mv * .. ; cd .. ; rm -rf guacamole-history-recording-storage-1.6.0 ; rm -rf guacamole-history-recording-storage-1.6.0.tar.gz LICENSE NOTICE ; cd ..


# 5. CONFIGURATION DOCKER
echo "[++++] Ecriture de la configuration... [++++]"

cat > docker-compose.yml <<EOF
services:

  # Base de données
  postgres:
    image: postgres:15-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: guacamole
      POSTGRES_PASSWORD: ${DB_PASS}
      POSTGRES_DB: guacamole_db
    volumes:
      - ./postgres:/var/lib/postgresql/data
      - ./initdb.sql:/docker-entrypoint-initdb.d/initdb.sql:ro
    networks:
      - internal
  # Base de données



  # Backend (RDP/SSH)
  guacd:
    image: guacamole/guacd:1.6.0
    restart: unless-stopped
    networks:
      - internal
    volumes:
      - ./recordings:/recordings:rw
      - ./drive:/drive:rw
# Backend


  # Frontend (Interface Web + LDAP + Extension Replay + Branding)
  guacamole:
    image: guacamole/guacamole:1.6.0
    restart: unless-stopped
    depends_on:
      - postgres
      - guacd
    ports:
      - "8080:8080"
    environment:
      GUACD_HOSTNAME: guacd
  # Frontend


      # --- CONFIGURATION POUR LE REPLAY ---
      RECORDING_SEARCH_PATH: "/recordings"
      # --- CONFIGURATION POUR LE REPLAY ---



      
      # --- PostgreSQL ---
      POSTGRESQL_HOSTNAME: postgres
      POSTGRESQL_DATABASE: guacamole_db
      POSTGRESQL_USERNAME: guacamole
      POSTGRESQL_PASSWORD: ${DB_PASS}
      POSTGRESQL_AUTO_CREATE_ACCOUNTS: "true"
      # --- PostgreSQL ---



      # --- LDAP ---
      LDAP_HOSTNAME: "X"
      LDAP_PORT: "389"
      LDAP_ENCRYPTION_METHOD: "none"
      LDAP_USER_BASE_DN: "ou=X,dc=X,dc=X"
      LDAP_GROUP_BASE_DN: "ou=X,dc=X,dc=X"
      LDAP_USERNAME_ATTRIBUTE: "uid"
      LDAP_MEMBER_ATTRIBUTE: "member"
      LDAP_USER_SEARCH_FILTER: "(objectClass=inetOrgPerson)"
      LDAP_SEARCH_BIND_DN: "uid=X,ou=X,dc=X,dc=X"
      LDAP_SEARCH_BIND_PASSWORD: "XXXXXXXX
      EXTENSION_PRIORITY: "jdbc,ldap"
      # --- LDAP ---


      # --- 2FA ---
      TOTP_ENABLED: "true"
      TOTP_ISSUER: "Guacamole"
      # --- 2FA ---
      
    volumes:
      - ./recordings:/recordings:rw
      - ./drive:/var/lib/guacamole/drive
      - ./extensions:/etc/guacamole/extensions:ro
    networks:
      - internal

networks:
  internal:
    driver: bridge
EOF

# 6. LANCEMENT
echo "[++++] Deploiement... [++++]"
docker compose up -d

echo ""
echo "---------------------------------------------------"
echo "   INSTALLATION GUACAMOLE 1.6.0 (COMPLETE) TERMINEE"
echo "---------------------------------------------------"
echo "1. Attendez ~30 secondes."
echo "2. Connectez-vous sur : http://<IP_SERVEUR>:8080/guacamole/"
echo "---------------------------------------------------"


# LESTIENNES Lucas
# 2026
