{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": __XRAY_INBOUNDS_JSON__,
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
