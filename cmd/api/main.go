package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os/signal"
	"syscall"
	"time"

	"github.com/bkjonathan/NearTrade/internal/config"
	"github.com/bkjonathan/NearTrade/internal/db"
	"github.com/bkjonathan/NearTrade/internal/handlers"
)

// shutdownTimeout bounds how long in-flight requests get to finish after
// SIGTERM. Keep it under the orchestrator's kill grace period (Docker: 10s
// by default, raised to 30s in docker-compose.yml).
const shutdownTimeout = 15 * time.Second

func main() {
	Config := config.MustLoadConfig()
	_, err := db.Connect(Config.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to connect to database: %v", err)
	}

	fmt.Println("Database connection established successfully.")
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", handlers.Health)

	srv := &http.Server{
		Addr:         ":" + Config.Port,
		Handler:      mux,
		ReadTimeout:  10 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  60 * time.Second,
	}

	// Registered before the server starts so a fast redeploy can't miss the signal.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	go func() {
		log.Printf("Starting server on port %s (env=%s)", Config.Port, Config.Env)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("Server failed to start: %v", err)
		}
	}()

	<-ctx.Done()
	log.Println("Shutdown signal received, draining connections...")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()

	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Fatalf("Graceful shutdown failed: %v", err)
	}
	log.Println("Server stopped cleanly")
}
