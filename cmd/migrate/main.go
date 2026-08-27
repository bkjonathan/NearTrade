package main

import (
	"fmt"
	"log"
	"os"

	"github.com/bkjonathan/NearTrade/internal/config"
	_ "github.com/jackc/pgx/v5/stdlib"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: migrate <up | down>")
		os.Exit(1)
	}

	Conf := config.MustLoadConfig()

	m, err := migrate.New(
		"file://migrations",
		Conf.DatabaseURL)
	if err != nil {
		log.Fatalf("Failed to create migrate instance: %v", err)
	}

	switch os.Args[1] {
	case "up":
		if err := m.Up(); err != nil {
			log.Fatalf("Failed to run migration up: %v", err)
		}
	case "down":
		if err := m.Down(); err != nil {
			log.Fatalf("Failed to run migration down: %v", err)
		}
	default:
		fmt.Println("Usage: migrate <up | down>")
		os.Exit(1)
	}

	fmt.Println("Migration completed successfully.")
}
