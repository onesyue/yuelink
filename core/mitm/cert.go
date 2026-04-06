package mitm

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"log"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

const (
	caCertFilename = "ca.crt"
	caKeyFilename  = "ca.key"
	caValidYears   = 10
)

// mitmDir returns the mitm data subdirectory under homeDir.
func mitmDir(homeDir string) string {
	return filepath.Join(homeDir, "mitm")
}

// caCertPath returns the full path to the CA certificate PEM file.
func caCertPath(homeDir string) string {
	return filepath.Join(mitmDir(homeDir), caCertFilename)
}

// caKeyPath returns the full path to the CA private key PEM file.
func caKeyPath(homeDir string) string {
	return filepath.Join(mitmDir(homeDir), caKeyFilename)
}

// GenerateRootCA creates or loads the Root CA cert.
// homeDir: the YueLink data directory (same as core homeDir).
// Returns CertStatus or error.
func GenerateRootCA(homeDir string) (*CertStatus, error) {
	dir := mitmDir(homeDir)
	certPath := caCertPath(homeDir)
	keyPath := caKeyPath(homeDir)

	// Attempt to reuse existing files if they are valid.
	if status := loadExistingCA(certPath, keyPath); status != nil {
		log.Printf("[MITM] Reusing existing Root CA (expires %s)", status.ExpiresAt.Format("2006-01-02"))
		return status, nil
	}

	// Ensure directory exists.
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("[MITM] failed to create mitm dir: %w", err)
	}

	log.Printf("[MITM] Generating new ECDSA P-256 Root CA …")

	// Generate ECDSA P-256 key pair.
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("[MITM] key generation failed: %w", err)
	}

	now := time.Now().UTC()
	expiry := now.Add(caValidYears * 365 * 24 * time.Hour)

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("[MITM] serial generation failed: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			Organization: []string{"YueLink"},
			CommonName:   "YueLink Module Runtime CA",
		},
		NotBefore:             now,
		NotAfter:              expiry,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            1,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &privKey.PublicKey, privKey)
	if err != nil {
		return nil, fmt.Errorf("[MITM] cert creation failed: %w", err)
	}

	// Write certificate PEM.
	certFile, err := os.OpenFile(certPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to open cert file: %w", err)
	}
	defer certFile.Close()
	if err := pem.Encode(certFile, &pem.Block{Type: "CERTIFICATE", Bytes: certDER}); err != nil {
		return nil, fmt.Errorf("[MITM] failed to write cert PEM: %w", err)
	}

	// Write private key PEM.
	keyDER, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to marshal private key: %w", err)
	}
	keyFile, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to open key file: %w", err)
	}
	defer keyFile.Close()
	if err := pem.Encode(keyFile, &pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}); err != nil {
		return nil, fmt.Errorf("[MITM] failed to write key PEM: %w", err)
	}

	fingerprint := sha256Fingerprint(certDER)
	log.Printf("[MITM] Root CA generated, fingerprint: %s", fingerprint)

	return &CertStatus{
		Exists:      true,
		Fingerprint: fingerprint,
		CreatedAt:   now,
		ExpiresAt:   expiry,
		PEMPath:     certPath,
	}, nil
}

// GetRootCAStatus returns current CA status without generating.
// Returns nil if CA doesn't exist or is invalid.
func GetRootCAStatus(homeDir string) *CertStatus {
	return loadExistingCA(caCertPath(homeDir), caKeyPath(homeDir))
}

// ExportRootCAPEM returns the CA certificate PEM bytes for installation.
func ExportRootCAPEM(homeDir string) ([]byte, error) {
	certPath := caCertPath(homeDir)
	data, err := os.ReadFile(certPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, errors.New("[MITM] CA certificate does not exist; call GenerateRootCA first")
		}
		return nil, fmt.Errorf("[MITM] failed to read CA cert: %w", err)
	}
	return data, nil
}

// loadExistingCA tries to parse the cert + key at the given paths.
// Returns nil if either file is missing, unreadable, or the cert is expired.
func loadExistingCA(certPath, keyPath string) *CertStatus {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil
	}
	if _, err := os.Stat(keyPath); err != nil {
		return nil // key file must also exist
	}

	block, _ := pem.Decode(certPEM)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil
	}
	if time.Now().After(cert.NotAfter) {
		log.Printf("[MITM] Existing CA expired on %s, will regenerate", cert.NotAfter.Format("2006-01-02"))
		return nil
	}

	return &CertStatus{
		Exists:      true,
		Fingerprint: sha256Fingerprint(block.Bytes),
		CreatedAt:   cert.NotBefore,
		ExpiresAt:   cert.NotAfter,
		PEMPath:     certPath,
	}
}

// sha256Fingerprint computes the colon-separated hex SHA-256 of raw DER bytes.
func sha256Fingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:])
}
