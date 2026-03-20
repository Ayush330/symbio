package auth

import (
	"context"
	"database/sql"
	"errors"

	"github.com/google/uuid"
)

var (
	ErrUserDuplicate = errors.New("user already exists")
	ErrUserNotFound  = errors.New("user not found")
)

type Repository interface {
	CreateUser(ctx context.Context, u *User) error
	GetUserByEmail(ctx context.Context, email string) (*User, error)
	GetUserByID(ctx context.Context, id uuid.UUID) (*User, error)
	UpdatePassword(ctx context.Context, userID uuid.UUID, passwordHash string) error
	SaveFCMToken(ctx context.Context, userID uuid.UUID, token string) error
}

type postgresRepository struct {
	db *sql.DB
}

func NewRepository(db *sql.DB) Repository {
	return &postgresRepository{db: db}
}

func (r *postgresRepository) CreateUser(ctx context.Context, u *User) error {
	query := `
		INSERT INTO users (email, passwd_hash, name, phone)
		VALUES ($1, $2, $3, $4)
		RETURNING id, created_at
	`
	err := r.db.QueryRowContext(
		ctx, query, u.Email, u.PasswdHash, u.Name, u.Phone,
	).Scan(&u.ID, &u.CreatedAt)

	if err != nil {
		if err.Error() == "pq: duplicate key value violates unique constraint \"users_email_key\"" {
			return ErrUserDuplicate
		}
		return err
	}
	return nil
}

func (r *postgresRepository) GetUserByEmail(ctx context.Context, email string) (*User, error) {
	query := `
		SELECT id, email, passwd_hash, name, phone, created_at, fcm_token
		FROM users
		WHERE email = $1
	`
	u := &User{}
	var phone, fcm sql.NullString
	err := r.db.QueryRowContext(ctx, query, email).Scan(
		&u.ID, &u.Email, &u.PasswdHash, &u.Name, &phone, &u.CreatedAt, &fcm,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	if phone.Valid {
		u.Phone = phone.String
	}
	if fcm.Valid {
		u.FCMToken = fcm.String
	}
	return u, nil
}

func (r *postgresRepository) GetUserByID(ctx context.Context, id uuid.UUID) (*User, error) {
	query := `
		SELECT id, email, passwd_hash, name, phone, created_at, fcm_token
		FROM users
		WHERE id = $1
	`
	u := &User{}
	var phone, fcm sql.NullString
	err := r.db.QueryRowContext(ctx, query, id).Scan(
		&u.ID, &u.Email, &u.PasswdHash, &u.Name, &phone, &u.CreatedAt, &fcm,
	)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrUserNotFound
		}
		return nil, err
	}
	if phone.Valid {
		u.Phone = phone.String
	}
	if fcm.Valid {
		u.FCMToken = fcm.String
	}
	return u, nil
}

func (r *postgresRepository) UpdatePassword(ctx context.Context, userID uuid.UUID, passwordHash string) error {
	query := `UPDATE users SET passwd_hash = $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, query, passwordHash, userID)
	return err
}

func (r *postgresRepository) SaveFCMToken(ctx context.Context, userID uuid.UUID, token string) error {
	query := `UPDATE users SET fcm_token = $1 WHERE id = $2`
	_, err := r.db.ExecContext(ctx, query, token, userID)
	return err
}
