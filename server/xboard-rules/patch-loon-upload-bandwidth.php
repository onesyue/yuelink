<?php
$p = '/www/app/Protocols/Loon.php';
$s = file_get_contents($p);
if (strpos($s, 'upload-bandwidth={$up}') !== false) {
    echo "already patched\n";
    exit(0);
}
$needle = <<<'TXT'
        if ($down = data_get($protocol_settings, 'bandwidth.down')) {
            $config[] = "download-bandwidth={$down}";
        }
TXT;
$replacement = <<<'TXT'
        if ($up = data_get($protocol_settings, 'bandwidth.up')) {
            $config[] = "upload-bandwidth={$up}";
        }
        if ($down = data_get($protocol_settings, 'bandwidth.down')) {
            $config[] = "download-bandwidth={$down}";
        }
TXT;
if (strpos($s, $needle) === false) {
    fwrite(STDERR, "needle not found\n");
    exit(1);
}
file_put_contents($p, str_replace($needle, $replacement, $s));
echo "patched\n";
