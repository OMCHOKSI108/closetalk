// wipe_users — deletes every non-admin user from the production database
// (and all their associated data). Admins are kept intact.
//
// Usage:
//   go run cmd/wipe_users/main.go              # dry-run, prints what would be deleted
//   go run cmd/wipe_users/main.go --confirm    # actually does it
package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/joho/godotenv"

	"github.com/OMCHOKSI108/closetalk/internal/database"
)

func main() {
	confirm := flag.Bool("confirm", false, "actually run the deletion (default is dry-run)")
	flag.Parse()

	godotenv.Load()
	if err := database.ConnectNeon(); err != nil {
		fmt.Printf("DB connection failed: %v\n", err)
		os.Exit(1)
	}
	defer database.CloseNeon()

	ctx := context.Background()

	// Pre-flight: how many users will go and how many we'll keep.
	var toDelete, keep int
	if err := database.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users WHERE is_admin = false`).Scan(&toDelete); err != nil {
		fmt.Printf("count(non-admins) failed: %v\n", err)
		os.Exit(1)
	}
	if err := database.Pool.QueryRow(ctx,
		`SELECT COUNT(*) FROM users WHERE is_admin = true`).Scan(&keep); err != nil {
		fmt.Printf("count(admins) failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Will DELETE %d non-admin users (keeping %d admins).\n", toDelete, keep)
	if !*confirm {
		fmt.Println("Dry-run only. Re-run with --confirm to apply.")
		return
	}

	tx, err := database.Pool.Begin(ctx)
	if err != nil {
		fmt.Printf("begin tx failed: %v\n", err)
		os.Exit(1)
	}
	defer tx.Rollback(ctx)

	// Order matters: clear references with no ON DELETE CASCADE first.
	// 1. Null out invited_by where it points to a non-admin (FK has no CASCADE).
	if _, err := tx.Exec(ctx, `
		UPDATE group_members
		SET invited_by = NULL
		WHERE invited_by IN (SELECT id FROM users WHERE is_admin = false)
	`); err != nil {
		fmt.Printf("step 1 (null invited_by) failed: %v\n", err)
		os.Exit(1)
	}

	// 2. Delete groups created by non-admins. Cascades to group_members,
	//    group_settings, pinned_messages within those groups.
	groupsDel, err := tx.Exec(ctx, `
		DELETE FROM groups
		WHERE created_by IN (SELECT id FROM users WHERE is_admin = false)
	`)
	if err != nil {
		fmt.Printf("step 2 (delete groups) failed: %v\n", err)
		os.Exit(1)
	}

	// 3. Delete pinned_messages pinned BY non-admins in groups that survived
	//    (i.e. admin-owned groups where a non-admin pinned something).
	pinDel, err := tx.Exec(ctx, `
		DELETE FROM pinned_messages
		WHERE pinned_by IN (SELECT id FROM users WHERE is_admin = false)
	`)
	if err != nil {
		fmt.Printf("step 3 (delete pinned_messages) failed: %v\n", err)
		os.Exit(1)
	}

	// 4. Finally, delete the users themselves. The remaining FKs all have
	//    ON DELETE CASCADE so this clears sessions, devices, contacts,
	//    conversation_participants, user_settings, etc.
	usersDel, err := tx.Exec(ctx, `DELETE FROM users WHERE is_admin = false`)
	if err != nil {
		fmt.Printf("step 4 (delete users) failed: %v\n", err)
		os.Exit(1)
	}

	if err := tx.Commit(ctx); err != nil {
		fmt.Printf("commit failed: %v\n", err)
		os.Exit(1)
	}

	fmt.Printf("Done.\n")
	fmt.Printf("  groups deleted:          %d\n", groupsDel.RowsAffected())
	fmt.Printf("  pinned_messages deleted: %d\n", pinDel.RowsAffected())
	fmt.Printf("  users deleted:           %d\n", usersDel.RowsAffected())
}
