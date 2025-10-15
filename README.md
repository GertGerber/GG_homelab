# GG_homelab

## Entrypoint
```bash
# Dry run:
bash -c "$(curl -fsSL https://raw.githubusercontent.com/GertGerber/GG_Homelab/v0.1.1/bootstrap.sh)" -- plan

# apply to dev
ENVIRONMENT=dev bash -c "$(curl -fsSL https://raw.githubusercontent.com/GertGerber/GG_Homelab/v0.1.0/bootstrap.sh)" -- apply

# destroy
bash -c "$(curl -fsSL https://raw.githubusercontent.com/GertGerber/GG_Homelab/v0.1.0/bootstrap.sh)" -- destroy

# pin to a specific commit (best for reproducibility)
bash -c "$(curl -fsSL https://raw.githubusercontent.com/GertGerber/GG_Homelab/<COMMIT_SHA>/bootstrap.sh)" -- plan


```

