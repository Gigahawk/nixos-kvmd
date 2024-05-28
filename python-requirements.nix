ps: with ps; [
    # Dependencies for main kvmd daemon
    aiofiles
    aiohttp
    async-lru
    dbus-next
    libgpiod
    passlib
    pillow
    psutil
    pygments
    pyotp
    pyyaml
    setproctitle
    systemd
    xlib
    xkbcommon  # TODO: do we need this or just libxkbcommon?
    zstandard

    # Dependencies for kvmd-oled
    cbor2
    luma-core
    luma-oled
    netifaces
    #psutil
    pillow
    pyftdi
    pyusb
    rpi-gpio2
    smbus2
    spidev
]