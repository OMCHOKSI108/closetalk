package main

import (
	"fmt"
	"os"

	"github.com/OMCHOKSI108/closetalk/internal/database"
	"github.com/joho/godotenv"
)

func main() {
	godotenv.Load()
	args := os.Args[1:]
	if len(args) < 1 {
		fmt.Println("Usage: go run cmd/make_admin/main.go <email>")
		os.Exit(1)
	}
	email := args[0]

	if err := database.ConnectNeon(); err != nil {
		fmt.Printf("DB connection failed: %v\n", err)
		os.Exit(1)
	}
	defer database.CloseNeon()

	result, err := database.Pool.Exec(nil,
		"UPDATE users SET is_admin = true WHERE email = $1", email)
	if err != nil {
		fmt.Printf("Update failed: %v\n", err)
		os.Exit(1)
	}
	if result.RowsAffected() == 0 {
		fmt.Printf("User '%s' not found. Register via the app first.\n", email)
		os.Exit(1)
	}
	fmt.Printf("User '%s' promoted to admin!\n", email)
}
