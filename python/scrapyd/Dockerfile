# 第一个阶段：构建阶段
FROM python:3.9.16-slim-buster AS builder

WORKDIR /app

# 安装构建依赖
RUN apk update && \
    apk add --no-cache gcc musl-dev libffi-dev

# 复制必要文件并安装依赖
COPY ./requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# 第二个阶段：运行时阶段
FROM python:3.9.16-slim-buster

WORKDIR /app

# 复制 scrapyd 配置文件
COPY ./scrapyd.conf /etc/scrapyd/

# 从构建阶段复制已安装的 Python 依赖
COPY --from=builder /usr/local/lib/python3.9/site-packages /usr/local/lib/python3.9/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

EXPOSE 6800

# 运行 scrapyd
CMD ["scrapyd"]