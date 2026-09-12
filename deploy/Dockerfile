FROM node:24-bookworm-slim
WORKDIR /app
COPY backend/ ./backend/
WORKDIR /app/backend
ENV PORT=8787
EXPOSE 8787
CMD ["npm","start"]
