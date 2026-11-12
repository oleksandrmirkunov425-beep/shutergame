FROM ubuntu:24.04

# Постав ТУ САМУ версію Godot, що й у твоєму редакторі (Help -> About)
ARG GODOT_TAG=4.6-stable

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget unzip ca-certificates libfontconfig1 \
    && rm -rf /var/lib/apt/lists/*

RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_TAG}/Godot_v${GODOT_TAG}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /tmp \
    && mv "/tmp/Godot_v${GODOT_TAG}_linux.x86_64" /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . .

# Імпорт ресурсів (.fbx, .jpg, ...) один раз під час збірки
RUN godot --headless --path /app --import || true

# Render сам підставляє PORT (за замовчуванням 10000)
ENV PORT=10000
EXPOSE 10000

CMD ["godot", "--headless", "--path", "/app", "--", "--server"]
