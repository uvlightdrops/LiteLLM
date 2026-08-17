#!/usr/bin/env python3
"""
CLI-Wrapper für yaml_config_support zur Füllung der LiteLLM Production-Kubernetes-Deployments.

Dieses Skript lädt die Basis-Template-Datei, kombiniert sie mit umgebungsspezifischen
Overlays und secret-Dateien und generiert fertige Kubernetes YAML-Dateien.

Nutzung:
    python k8s_fill_config.py dev
    python k8s_fill_config.py staging --outdir ./generated-k8s
    python k8s_fill_config.py prod
"""

import sys
from pathlib import Path

# yaml_config_support importieren
sys.path.insert(0, "/home/flow/dev_flow/yaml_config_support")

from yaml_config_support.k8sValuesFill import K8sValuesFill
from yaml_config_support.config_models import FillOptions

# Pfade definieren
SCRIPT_DIR = Path(__file__).parent
TEMPLATE_DIR = SCRIPT_DIR / "prod" / "templates"
VALUESTORE_DIR = Path.home() / "dev_data" / "LiteLLM"
OUTPUT_DIR = SCRIPT_DIR / "prod" / "generated"

# Optional override via env variable for a different secure secrets directory.
VALUESTORE_DIR = Path(__import__("os").environ.get("LITELLM_SECRET_DIR", str(VALUESTORE_DIR)))


def create_fill_options(environment: str, outdir: str = None) -> FillOptions:
    """
    Erstelle FillOptions für die LiteLLM K8s-Deployment-Konfiguration.
    
    Args:
        environment: 'dev', 'staging' oder 'prod'
        outdir: Optional, überschreibt OUTPUT_DIR
    
    Returns:
        FillOptions-Objekt mit allen Konfigurationen
    """
    
    # Datenquellen in Reihenfolge ihrer Anwendung
    data_files = {
        "creds": {
            "source": "private",
            "transform": "fill_config_template",
            "env": "yes",
            "file": "values_creds_{env}.yaml",
            "targets": ["*"],
        },
        "resources": {
            "source": "project",
            "transform": "fill_simple_template",
            "env": "together",
            "file": "values_resources.yaml",
            "targets": ["*"],
        },
        "ingress": {
            "source": "project",
            "transform": "fill_simple_template",
            "env": "together",
            "file": "values_ingress.yaml",
            "targets": ["*"],
        },
    }

    return FillOptions.from_mapping({
        "default_template_dir": TEMPLATE_DIR,
        "default_valuestore_dir": VALUESTORE_DIR,
        "outpath": Path(outdir) if outdir else OUTPUT_DIR,
        "data_files": data_files,
    })


def main():
    """
    Haupteinstiegspunkt für die CLI.
    """
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    
    environment = sys.argv[1]
    outdir = None
    
    # Parse optional --outdir
    for i, arg in enumerate(sys.argv[2:], 2):
        if arg == "--outdir" and i + 1 < len(sys.argv):
            outdir = sys.argv[i + 1]
            break
    
    if environment not in ["dev", "staging", "prod"]:
        print(f"Fehler: Umgebung '{environment}' nicht erkannt.")
        print("Unterstützte Umgebungen: dev, staging, prod")
        sys.exit(1)
    
    print(f"Füllen der LiteLLM K8s-Konfigurationen für Umgebung: {environment}")
    print(f"Template-Verzeichnis: {TEMPLATE_DIR}")
    print(f"Value-Store-Verzeichnis: {VALUESTORE_DIR}")
    print(f"Ausgabeverzeichnis: {outdir or OUTPUT_DIR}")
    print()
    
    try:
        options = create_fill_options(environment, outdir)
        filler = K8sValuesFill(environment, str(TEMPLATE_DIR), str(VALUESTORE_DIR), options)
        result_file = filler.run(Path(outdir) if outdir else OUTPUT_DIR)

        print(f"✓ Konfiguration erfolgreich gefüllt!")
        print(f"  Ergebnis: {result_file}")
        
    except FileNotFoundError as e:
        print(f"✗ Fehler: {e}")
        print("  Stelle sicher, dass Template-Dateien und Value-Store vorhanden sind.")
        sys.exit(1)
    except Exception as e:
        print(f"✗ Fehler beim Füllen der Konfiguration: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
