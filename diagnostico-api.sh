#!/usr/bin/env bash
# Diagnóstico somente-leitura da API amor animal.
# Uso: sudo bash diagnostico-api.sh
set -u

DOMINIO="api.projetosdinamicos.com.br"
PORTA_LOCAL="${PORTA_LOCAL:-3002}"
CONTAINER="${CONTAINER:-amoranimal-api}"

echo "== 1. DNS =="
DNSIP=$(getent hosts "$DOMINIO" | awk '{print $1; exit}')
echo "$DOMINIO -> ${DNSIP:-SEM RESOLUCAO}"

echo
echo "== 2. IPs na interface do servidor =="
ip -4 -o addr show scope global | awk '{print "  " $2 " " $4}'

echo
echo "== 3. IP publico de saida (egress) =="
EGRESS=$(curl -s --max-time 8 https://api.ipify.org 2>/dev/null)
echo "  ${EGRESS:-falha ao consultar}"

echo
echo "== 4. Portas escutando =="
sudo ss -tlnp 2>/dev/null | grep -E ":(${PORTA_LOCAL}|80|443)\b" || echo "  nada escutando em ${PORTA_LOCAL}/80/443"

echo
echo "== 5. API local (dentro do servidor) =="
for rota in /health /voluntario /amoranimal/voluntario; do
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "http://127.0.0.1:${PORTA_LOCAL}${rota}" 2>/dev/null)
    echo "  GET ${rota} -> ${code:-falha}"
done

echo
echo "== 6. Proxy local (SNI e Host corretos) =="
curl -k -s -o /dev/null -w "  https://${DOMINIO}/amoranimal/voluntario -> %{http_code}\n" \
    --max-time 8 --resolve "${DOMINIO}:443:127.0.0.1" \
    "https://${DOMINIO}/amoranimal/voluntario" 2>/dev/null \
    || echo "  falha ao conectar no proxy local"

echo
echo "== 7. CORS respondido pela API local =="
curl -s -o /dev/null -D - --max-time 8 \
    -H "Origin: https://amoranimal.ong.br" \
    "http://127.0.0.1:${PORTA_LOCAL}/voluntario" 2>/dev/null \
    | grep -iE '^HTTP|access-control-allow-origin' | sed 's/^/  /' \
    || echo "  API local nao respondeu"

echo
echo "== 7b. Validacao da config do nginx =="
sudo nginx -t 2>&1 | sed 's/^/  /' || echo "  nginx -t FALHOU (config invalida)"

echo
echo "== 8. Servicos de ingress =="
for s in nginx caddy cloudflared traefik; do
    if systemctl list-unit-files 2>/dev/null | grep -q "^${s}"; then
        echo "  ${s}: $(systemctl is-active "$s" 2>/dev/null)"
    fi
done

echo
echo "== 9. Container =="
sudo docker inspect "$CONTAINER" \
    --format '  status={{.State.Status}} health={{.State.Health.Status}} restarts={{.RestartCount}} started={{.State.StartedAt}}' \
    2>/dev/null || echo "  container ${CONTAINER} nao encontrado"

echo
echo "== 10. Firewall =="
sudo ufw status 2>/dev/null | head -5 | sed 's/^/  /' || true

echo
echo "== 11. Vhost do dominio =="
sudo nginx -T 2>/dev/null | grep -n -A20 "server_name .*${DOMINIO}" | head -40 | sed 's/^/  /' \
    || echo "  sem vhost nginx para ${DOMINIO}"

echo
echo "== CONCLUSAO =="
if [ -n "${DNSIP:-}" ] && ip -4 -o addr show scope global | grep -q " ${DNSIP}/"; then
    echo "  OK: ${DNSIP} esta em uma interface do servidor (entrada direta possivel)."
else
    echo "  ATENCAO: ${DNSIP:-?} NAO esta em nenhuma interface."
    echo "  -> o DNS aponta para IP de NAT/outro host; conexoes de entrada nao chegam aqui."
    if [ -n "${EGRESS:-}" ] && [ "${EGRESS}" = "${DNSIP:-}" ]; then
        echo "  -> e o mesmo IP de saida (egress): tipico de NAT compartilhado."
        echo "     Solucao: IP publico dedicado, Load Balancer ou Cloudflare Tunnel."
    fi
fi
