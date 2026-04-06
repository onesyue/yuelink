package mitm

import "log"

const (
	prefixMITM   = "[MITM]"
	prefixModule = "[ModuleRuntime]"
	prefixParser = "[ModuleParser]"
	prefixCA     = "[MITM][CA]"
	prefixEngine = "[MITM][Engine]"
	prefixConfig = "[MITM][Config]"
)

func logMitm(format string, args ...interface{}) {
	log.Printf(prefixMITM+" "+format, args...)
}

func logEngine(format string, args ...interface{}) {
	log.Printf(prefixEngine+" "+format, args...)
}

func logCA(format string, args ...interface{}) {
	log.Printf(prefixCA+" "+format, args...)
}

func logConfig(format string, args ...interface{}) {
	log.Printf(prefixConfig+" "+format, args...)
}
