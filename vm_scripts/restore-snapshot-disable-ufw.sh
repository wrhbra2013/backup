#!/bin/bash

echo "=== Restaurar Snapshot Magalu Cloud ==="
echo ""

echo "Fazendo login..."
mgc auth login

echo ""
echo "=== Selecione o Snapshot ==="
echo ""

mgc virtual-machine snapshots list -o table 2>/dev/null || mgc virtual-machine snapshots list

echo ""
read -p "ID do snapshot: " SNAPSHOT_ID

echo ""
echo "=== Selecione o Machine Type ==="
echo ""

mgc virtual-machine machine-types list -o table 2>/dev/null || mgc virtual-machine machine-types list

echo ""
read -p "Nome do machine-type: " MACHINE_TYPE

echo ""
echo "=== Selecione a VPC ==="
echo ""

mgc network vpcs list -o table 2>/dev/null || mgc network vpcs list

echo ""
read -p "Nome da VPC: " VPC_NAME

echo ""
echo "=== Selecione a Chave SSH ==="
echo ""

mgc profile ssh-keys list -o table 2>/dev/null || mgc profile ssh-keys list

echo ""
read -p "Nome da chave SSH: " SSH_KEY

echo ""
read -p "Nome da nova instancia: " INSTANCE_NAME

echo ""
read -p "Associar IP pubblico? (s/n): " ASSIGN_PUBLIC_IP

if [[ "$ASSIGN_PUBLIC_IP" =~ ^[Ss]$ ]]; then
    PUBLIC_IP="true"
else
    PUBLIC_IP="false"
fi

echo ""
echo "=== Criando user-data para desabilitar ufw ==="

USER_DATA_SCRIPT="#!/bin/bash
ufw disable"

USER_DATA_B64=$(echo "$USER_DATA_SCRIPT" | base64 -w 0)

echo ""
echo "=== Restaurando snapshot ==="
echo ""

mgc virtual-machine snapshots restore \
  --id="$SNAPSHOT_ID" \
  --name="$INSTANCE_NAME" \
  --machine-type.name="$MACHINE_TYPE" \
  --network.associate-public-ip="$PUBLIC_IP" \
  --network.vpc.name="$VPC_NAME" \
  --ssh-key-name="$SSH_KEY" \
  --user-data="$USER_DATA_B64"

echo ""
echo "Restauração concluida!"