#!/bin/bash
cat > /etc/systemd/system/bt-connect.service <<'EOF'
[Unit]
Description=Conectar Bluetooth automaticamente
After=bluetooth.service
Requires=bluetooth.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/bt-device -c 67:F0:01:5D:BC:31
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now bt-connect
echo "Servico criado e ativado com sucesso!"
