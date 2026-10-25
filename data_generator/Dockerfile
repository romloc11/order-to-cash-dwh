FROM python:3.12-slim
WORKDIR /app
COPY data_generator/ /app/data_generator/
# Standard library only: nothing to install.
ENTRYPOINT ["python", "-m", "data_generator.generate"]
CMD ["--out", "/out"]
