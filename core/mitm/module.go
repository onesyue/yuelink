package mitm

import "strings"

const mitmProxyName = "_mitm_engine"

// HostnameRules converts a list of ModuleRecords into mihomo rule strings
// that route MITM-targeted hostnames to the _mitm_engine proxy.
// Only enabled modules are included.
//
// Hostname prefix conventions:
//   - ".example.com"  → DOMAIN-SUFFIX,example.com,_mitm_engine
//   - "*.example.com" → DOMAIN-SUFFIX,example.com,_mitm_engine
//   - "api.example.com" → DOMAIN,api.example.com,_mitm_engine
//
// The returned slice is deduplicated (first occurrence wins).
func HostnameRules(modules []ModuleRecord) []string {
	seen := make(map[string]struct{})
	rules := make([]string, 0)

	for i := range modules {
		if !modules[i].Enabled {
			continue
		}
		for _, hostname := range modules[i].MITMHostnames {
			hostname = strings.TrimSpace(hostname)
			if hostname == "" {
				continue
			}
			var rule string
			switch {
			case strings.HasPrefix(hostname, "*."):
				// *.example.com → DOMAIN-SUFFIX,example.com
				rule = "DOMAIN-SUFFIX," + hostname[2:] + "," + mitmProxyName
			case strings.HasPrefix(hostname, "."):
				// .example.com → DOMAIN-SUFFIX,example.com
				rule = "DOMAIN-SUFFIX," + hostname[1:] + "," + mitmProxyName
			default:
				// exact hostname
				rule = "DOMAIN," + hostname + "," + mitmProxyName
			}
			if _, dup := seen[rule]; dup {
				continue
			}
			seen[rule] = struct{}{}
			rules = append(rules, rule)
		}
	}
	return rules
}

// ExtractAllMitmHostnames returns deduplicated MITM hostnames from all enabled
// modules. The hostnames are returned in their original form (with leading "."
// or "*." intact).
func ExtractAllMitmHostnames(modules []ModuleRecord) []string {
	seen := make(map[string]struct{})
	result := make([]string, 0)

	for i := range modules {
		if !modules[i].Enabled {
			continue
		}
		for _, hostname := range modules[i].MITMHostnames {
			hostname = strings.TrimSpace(hostname)
			if hostname == "" {
				continue
			}
			if _, dup := seen[hostname]; dup {
				continue
			}
			seen[hostname] = struct{}{}
			result = append(result, hostname)
		}
	}
	return result
}

// EnabledRules returns plain (non-MITM) rules from all enabled modules, in the
// order they appear across modules. Duplicates are preserved so that
// rule priority is not silently changed.
func EnabledRules(modules []ModuleRecord) []string {
	var result []string
	for i := range modules {
		if !modules[i].Enabled {
			continue
		}
		for j := range modules[i].Rules {
			raw := strings.TrimSpace(modules[i].Rules[j].Raw)
			if raw != "" {
				result = append(result, raw)
			}
		}
	}
	return result
}
