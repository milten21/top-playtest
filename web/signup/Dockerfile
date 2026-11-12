FROM python:3-slim
RUN pip install --no-cache-dir "psycopg[binary]==3.3.9"
COPY signup.py /app/signup.py
USER nobody
CMD ["python", "-u", "/app/signup.py"]
