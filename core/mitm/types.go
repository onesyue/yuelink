package mitm

import "time"

// ModuleRule represents a single rule entry from [Rule] section
type ModuleRule struct {
	Raw     string `json:"raw"`
	Type    string `json:"type"`             // DOMAIN, DOMAIN-SUFFIX, IP-CIDR, etc.
	Target  string `json:"target"`           // the domain/IP
	Action  string `json:"action"`           // REJECT, DIRECT, proxy group name
	Options string `json:"options,omitempty"` // e.g. no-resolve
}

// UrlRewriteRule from [URL Rewrite] section
type UrlRewriteRule struct {
	Pattern     string `json:"pattern"`
	Replacement string `json:"replacement,omitempty"`
	RewriteType string `json:"rewrite_type"` // reject, 302, 307, header
	Raw         string `json:"raw"`
}

// HeaderRewriteRule from [Header Rewrite] section
type HeaderRewriteRule struct {
	Pattern      string `json:"pattern"`
	HeaderAction string `json:"header_action"` // header-replace, header-add, header-del
	HeaderName   string `json:"header_name,omitempty"`
	HeaderValue  string `json:"header_value,omitempty"`
	Raw          string `json:"raw"`
}

// ModuleScript from [Script] section
type ModuleScript struct {
	Name           string `json:"name"`
	ScriptType     string `json:"script_type"` // http-request, http-response, cron, generic
	Pattern        string `json:"pattern,omitempty"`
	ScriptPath     string `json:"script_path"`
	RequiresBody   bool   `json:"requires_body"`
	CronExpression string `json:"cron_expression,omitempty"`
	Raw            string `json:"raw"`
}

// MapLocalRule from [Map Local] section
type MapLocalRule struct {
	Pattern string `json:"pattern"`
	DataUrl string `json:"data_url"`
	Raw     string `json:"raw"`
}

// UnsupportedCounts tracks capabilities that aren't yet active
type UnsupportedCounts struct {
	MITMCount          int `json:"mitm_count"`
	URLRewriteCount    int `json:"url_rewrite_count"`
	HeaderRewriteCount int `json:"header_rewrite_count"`
	ScriptCount        int `json:"script_count"`
	MapLocalCount      int `json:"map_local_count"`
	PanelCount         int `json:"panel_count"`
}

func (u UnsupportedCounts) Total() int {
	return u.MITMCount + u.URLRewriteCount + u.HeaderRewriteCount +
		u.ScriptCount + u.MapLocalCount + u.PanelCount
}

// ModuleRecord is the persisted module entity
type ModuleRecord struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	Desc     string `json:"desc"`
	SourceURL string `json:"source_url"`
	Checksum string `json:"checksum"`
	Enabled  bool   `json:"enabled"`

	VersionTag string `json:"version_tag,omitempty"`
	Author     string `json:"author,omitempty"`
	IconURL    string `json:"icon_url,omitempty"`
	Homepage   string `json:"homepage,omitempty"`
	Category   string `json:"category,omitempty"`

	Rules          []ModuleRule        `json:"rules"`
	MITMHostnames  []string            `json:"mitm_hostnames"`
	URLRewrites    []UrlRewriteRule    `json:"url_rewrites"`
	HeaderRewrites []HeaderRewriteRule `json:"header_rewrites"`
	Scripts        []ModuleScript      `json:"scripts"`
	MapLocals      []MapLocalRule      `json:"map_locals"`

	UnsupportedCounts UnsupportedCounts `json:"unsupported_counts"`
	ParseWarnings     []string          `json:"parse_warnings"`

	CreatedAt     time.Time  `json:"created_at"`
	UpdatedAt     time.Time  `json:"updated_at"`
	LastFetchedAt *time.Time `json:"last_fetched_at,omitempty"`
	LastAppliedAt *time.Time `json:"last_applied_at,omitempty"`
}

// CertStatus holds CA certificate information
type CertStatus struct {
	Exists      bool      `json:"exists"`
	Fingerprint string    `json:"fingerprint"` // SHA256, hex
	CreatedAt   time.Time `json:"created_at"`
	ExpiresAt   time.Time `json:"expires_at"`
	PEMPath     string    `json:"pem_path"`
}

// EngineStatus holds MITM engine state
type EngineStatus struct {
	Running bool   `json:"running"`
	Port    int    `json:"port"`
	Address string `json:"address"` // "127.0.0.1:9091"
}
