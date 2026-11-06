FROM python:3.12-alpine
WORKDIR /app
COPY server.py /app/server.py
ENV PORT=8090 TRIGGERS_DIR=/triggers REPO_ROOT=/repo
EXPOSE 8090
USER nobody
CMD ["python", "-u", "/app/server.py"]
