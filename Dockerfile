FROM python:3.11-slim

WORKDIR /app

COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code and web app
COPY backend/ ./backend/
COPY web-app/ ./web-app/

WORKDIR /app/backend

EXPOSE 8080

CMD ["python", "server.py"]
