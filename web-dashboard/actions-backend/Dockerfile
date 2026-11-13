FROM python:3.12-alpine
WORKDIR /app
COPY server.py /app/server.py
ENV PORT=8090 TRIGGERS_DIR=/triggers REPO_ROOT=/repo
EXPOSE 8090
# The server starts as root so it can make the bind-mounted /triggers writable
# for the unprivileged user, then drops to 'nobody' before serving (see
# server.py main()). USER nobody is intentionally not set here: the bind mount
# must be chmod'ed while root.
CMD ["python", "-u", "/app/server.py"]
