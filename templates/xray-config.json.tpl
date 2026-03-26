{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "listen": "__XRAY_LISTEN_ADDR__",
      "port": __XRAY_PORT__,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "__XRAY_UUID__",
            "flow": "xtls-rprx-vision",
            "email": "default@neflare"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "__REALITY_DEST__",
          "xver": 0,
          "serverNames": __REALITY_SERVER_NAMES_JSON__,
          "privateKey": "__XRAY_PRIVATE_KEY__",
          "shortIds": __XRAY_SHORT_IDS_JSON__
        },
        "rawSettings": {
          "acceptProxyProtocol": false,
          "header": {
            "type": "none"
          }
        }
      },
      "sniffing": {
        "enabled": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}

