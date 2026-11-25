// Package storage keeps photos, voice messages and chat pictures in an
// S3-compatible bucket.
//
// Files never pass through the API: a client asks for an upload URL,
// sends the file straight to storage, then refers to it by its key.
// Reading goes through the API, which checks the reader may see it and
// redirects to a short-lived download URL.
package storage

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net/url"
	"time"

	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

type Config struct {
	// Where the API reaches storage, e.g. localhost:8333.
	Endpoint string
	// Where phones reach storage, for the signed URLs. Defaults to
	// Endpoint.
	PublicEndpoint string
	AccessKey      string
	SecretKey      string
	Bucket         string
	UseSSL         bool
	// Cloudflare R2 uses "auto"; empty asks the server.
	Region string
	// Make the bucket if missing. Off where the bucket is set up by hand
	// and the key may not create buckets, as on R2.
	CreateBucket bool
}

// Kind is what a file is; it decides where it goes and how big it may be.
type Kind struct {
	Folder       string
	MaxBytes     int64
	ContentTypes []string
}

var (
	Image  = Kind{"images", 15 << 20, []string{"image/jpeg", "image/png", "image/webp", "image/heic"}}
	Voice  = Kind{"audio", 25 << 20, []string{"audio/mp4", "audio/m4a", "audio/aac", "audio/mpeg", "audio/ogg"}}
	Avatar = Kind{"avatar", 5 << 20, []string{"image/jpeg", "image/png", "image/webp"}}
)

var ErrTooBig = errors.New("file is too big")

type Storage struct {
	client *minio.Client // talks to storage
	signer *minio.Client // signs URLs for the public address
	bucket string
}

const uploadTTL = 15 * time.Minute
const downloadTTL = time.Hour

func New(ctx context.Context, cfg Config) (*Storage, error) {
	creds := credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, "")
	client, err := minio.New(cfg.Endpoint, &minio.Options{Creds: creds, Secure: cfg.UseSSL, Region: cfg.Region})
	if err != nil {
		return nil, err
	}
	signer := client
	if cfg.PublicEndpoint != "" && cfg.PublicEndpoint != cfg.Endpoint {
		// Region set so signing needs no round trip to the public address.
		region := cfg.Region
		if region == "" {
			region = "us-east-1"
		}
		signer, err = minio.New(cfg.PublicEndpoint, &minio.Options{
			Creds: creds, Secure: cfg.UseSSL, Region: region,
		})
		if err != nil {
			return nil, err
		}
	}

	exists, err := client.BucketExists(ctx, cfg.Bucket)
	if err != nil {
		return nil, fmt.Errorf("reach storage: %w", err)
	}
	if !exists && !cfg.CreateBucket {
		return nil, fmt.Errorf("bucket %q does not exist", cfg.Bucket)
	}
	if !exists {
		if err := client.MakeBucket(ctx, cfg.Bucket, minio.MakeBucketOptions{}); err != nil {
			return nil, fmt.Errorf("create bucket: %w", err)
		}
	}
	return &Storage{client: client, signer: signer, bucket: cfg.Bucket}, nil
}

// Upload is where to send a file and how to refer to it afterwards.
type Upload struct {
	Key       string    `json:"key"`
	URL       string    `json:"uploadUrl"`
	Method    string    `json:"method"`
	ExpiresAt time.Time `json:"expiresAt"`
}

// NewUpload picks a key under prefix (e.g. "chats/ABC123") for a new file
// and signs a URL to PUT it to.
func (s *Storage) NewUpload(ctx context.Context, prefix string, kind Kind, contentType string) (Upload, error) {
	if !allowed(kind, contentType) {
		return Upload{}, fmt.Errorf("type %q not allowed", contentType)
	}
	random := make([]byte, 12)
	rand.Read(random)
	key := fmt.Sprintf("%s/%s/%d_%s", prefix, kind.Folder, time.Now().UnixMilli(), hex.EncodeToString(random))
	u, err := s.signer.PresignedPutObject(ctx, s.bucket, key, uploadTTL)
	if err != nil {
		return Upload{}, err
	}
	return Upload{Key: key, URL: u.String(), Method: "PUT", ExpiresAt: time.Now().Add(uploadTTL)}, nil
}

func allowed(kind Kind, contentType string) bool {
	for _, t := range kind.ContentTypes {
		if t == contentType {
			return true
		}
	}
	return false
}

// Check confirms an uploaded file exists and isn't over the limit; a
// signed PUT can't cap the size by itself. Files over it are removed.
func (s *Storage) Check(ctx context.Context, key string, kind Kind) error {
	info, err := s.client.StatObject(ctx, s.bucket, key, minio.StatObjectOptions{})
	if err != nil {
		return fmt.Errorf("file not uploaded: %w", err)
	}
	if info.Size > kind.MaxBytes {
		s.Delete(ctx, key)
		return ErrTooBig
	}
	return nil
}

// DownloadURL signs a short-lived URL to read a file.
func (s *Storage) DownloadURL(ctx context.Context, key string) (string, error) {
	u, err := s.signer.PresignedGetObject(ctx, s.bucket, key, downloadTTL, url.Values{})
	if err != nil {
		return "", err
	}
	return u.String(), nil
}

func (s *Storage) Delete(ctx context.Context, key string) error {
	return s.client.RemoveObject(ctx, s.bucket, key, minio.RemoveObjectOptions{})
}

// DeleteAll removes every file under prefix, e.g. a deleted chat's.
func (s *Storage) DeleteAll(ctx context.Context, prefix string) {
	objects := s.client.ListObjects(ctx, s.bucket, minio.ListObjectsOptions{Prefix: prefix + "/", Recursive: true})
	for err := range s.client.RemoveObjects(ctx, s.bucket, objects, minio.RemoveObjectsOptions{}) {
		_ = err // best effort; leftovers are harmless
	}
}
