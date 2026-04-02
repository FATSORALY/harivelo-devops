#!/bin/bash

JENKINS_URL="http://localhost:8080"
JENKINS_USER="admin"
JENKINS_PASS=$(docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword 2>/dev/null)

# Demander les informations
echo "Configuration du credential Bitbucket"
echo "====================================="
read -p "Email ou nom d'utilisateur Bitbucket: " BITBUCKET_USER
read -sp "Mot de passe ou App Password Bitbucket: " BITBUCKET_PASS
echo ""

# Créer le fichier XML pour le credential
cat > bitbucket-credential.xml << XML
<com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
  <scope>GLOBAL</scope>
  <id>bitbucket-credentials</id>
  <description>Bitbucket Credentials for devops repository</description>
  <username>$BITBUCKET_USER</username>
  <password>$BITBUCKET_PASS</password>
</com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl>
XML

# Ajouter le credential via API
curl -X POST "$JENKINS_URL/credentials/store/system/domain/_/createCredentials" \
  --user "$JENKINS_USER:$JENKINS_PASS" \
  -H "Content-Type: application/xml" \
  --data-binary @bitbucket-credential.xml

echo "✅ Credential Bitbucket ajouté avec succès !"
