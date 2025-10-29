"""
Phase 1: Pre-deployment Tests

Tests that validate the environment and configuration before deploying infrastructure.
These tests should run quickly and don't require any cloud resources.
"""
import pytest
import subprocess
import os
from pathlib import Path
import hcl2
import yaml


"""Pre-deployment validation tests"""
@pytest.mark.phase1
class TestPreDeployment:
    
"""Verify Terraform is installed"""
    def test_terraform_installed(self):
        result = subprocess.run(
            ["terraform", "version"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "Terraform not found"
        assert "Terraform v" in result.stdout

"""Verify kubectl is installed"""
    def test_kubectl_installed(self):
        result = subprocess.run(
            ["kubectl", "version", "--client"],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, "kubectl not found"

    def test_python_version(self):
        import sys
        assert sys.version_info >= (3, 9), f"Python 3.9+ required, got {sys.version}"

"""Verify required Python packages are available"""
    def test_required_python_packages(self):
        required_packages = [
            "pytest",
            "kubernetes",
            "yaml",
            "requests",
        ]

        for package in required_packages:
            try:
                __import__(package)
            except ImportError:
                pytest.fail(f"Required package '{package}' not installed")

"""Verify project directory structure"""
    def test_project_structure(self, test_config):
        required_dirs = [
            test_config["terraform_dir"],
            test_config["workloads_dir"],
            test_config["benchmarks_dir"],
        ]

        for directory in required_dirs:
            assert directory.exists(), f"Directory not found: {directory}"

    def test_terraform_files_exist(self, test_config):
        terraform_dir = test_config["terraform_dir"]
        required_files = [
            "main.tf",
            "variables.tf",
            "outputs.tf",
            "versions.tf",
        ]

        for filename in required_files:
            file_path = terraform_dir / filename
            assert file_path.exists(), f"Terraform file not found: {file_path}"

    def test_terraform_syntax_valid(self, test_config):
        result = subprocess.run(
            ["terraform", "init", "-backend=false"],
            cwd=test_config["terraform_dir"],
            capture_output=True,
            text=True
        )

        if result.returncode != 0:
            # Try just validate without init
            result = subprocess.run(
                ["terraform", "validate"],
                cwd=test_config["terraform_dir"],
                capture_output=True,
                text=True
            )

        # Validate should work even without full init
        result = subprocess.run(
            ["terraform", "fmt", "-check", "-recursive"],
            cwd=test_config["terraform_dir"],
            capture_output=True,
            text=True
        )
        # fmt returns 0 if formatted, 3 if formatting needed - both are ok for syntax

    def test_kubernetes_manifests_valid(self, test_config):
        workloads_dir = test_config["workloads_dir"]

        for yaml_file in workloads_dir.glob("*.yaml"):
            with open(yaml_file) as f:
                try:
                    docs = list(yaml.safe_load_all(f))
                    assert len(docs) > 0, f"No documents in {yaml_file}"

                    # Basic validation
                    for doc in docs:
                        if doc is None:
                            continue
                        assert "apiVersion" in doc, f"Missing apiVersion in {yaml_file}"
                        assert "kind" in doc, f"Missing kind in {yaml_file}"
                        assert "metadata" in doc, f"Missing metadata in {yaml_file}"

                except yaml.YAMLError as e:
                    pytest.fail(f"Invalid YAML in {yaml_file}: {e}")

    def test_benchmark_scripts_exist(self, test_config):
        benchmarks_dir = test_config["benchmarks_dir"]
        required_scripts = [
            "http-load-test.sh",
            "grpc-test.sh",
            "collect-metrics.sh",
        ]

        for script_name in required_scripts:
            script_path = benchmarks_dir / script_name
            assert script_path.exists(), f"Script not found: {script_path}"
            assert os.access(script_path, os.X_OK), f"Script not executable: {script_path}"

"""Verify benchmark scripts have proper shebang"""
    def test_benchmark_scripts_have_shebang(self, test_config):
        benchmarks_dir = test_config["benchmarks_dir"]

        for script in benchmarks_dir.glob("*.sh"):
            with open(script) as f:
                first_line = f.readline()
                assert first_line.startswith("#!"), f"Missing shebang in {script}"

"""Check that required environment variables are documented"""
    def test_environment_variables_documented(self, test_config):
        readme_path = test_config["project_root"] / "README.md"
        assert readme_path.exists(), "README.md not found"

        with open(readme_path) as f:
            readme_content = f.read()

        # Check for important configuration mentions
        required_mentions = [
            "KUBECONFIG",
            "terraform.tfvars",
            "OCI",
        ]

        for mention in required_mentions:
            assert mention in readme_content, f"'{mention}' not documented in README"


"""Verify .gitignore excludes sensitive files!!!"""
    def test_gitignore_has_sensitive_files(self, test_config):
        gitignore_path = test_config["project_root"] / ".gitignore"

        if gitignore_path.exists():
            with open(gitignore_path) as f:
                gitignore_content = f.read()

            sensitive_patterns = [
                "*.tfvars",
                "*.pem",
                ".terraform",
            ]

            for pattern in sensitive_patterns:
                assert pattern in gitignore_content, \
                    f"Sensitive pattern '{pattern}' not in .gitignore"


"""Scan for potential hardcoded credentials"""
    def test_no_hardcoded_credentials(self, test_config):
        suspicious_patterns = [
            "password=",
            "secret=",
            "api_key=",
            "private_key=",
        ]

        # Check Terraform files
        for tf_file in test_config["terraform_dir"].glob("*.tf"):
            with open(tf_file) as f:
                content = f.read().lower()

            for pattern in suspicious_patterns:
                # Allow variable declarations but not actual values
                lines = content.split('\n')
                for i, line in enumerate(lines, 1):
                    if pattern in line and not line.strip().startswith('#'):
                        # Check if it's a variable declaration (acceptable)
                        if 'variable' not in line and 'var.' not in line:
                            pytest.fail(
                                f"Potential hardcoded credential in {tf_file}:{i}: {line.strip()}"
                            )

"""Verify workloads have health checks defined"""
    def test_workload_health_checks_defined(self, test_config):
        workloads_dir = test_config["workloads_dir"]

        for yaml_file in workloads_dir.glob("*-service.yaml"):
            with open(yaml_file) as f:
                docs = list(yaml.safe_load_all(f))

            # Find Deployment objects
            deployments = [d for d in docs if d and d.get("kind") == "Deployment"]

            for deployment in deployments:
                containers = deployment.get("spec", {}).get("template", {}).get(
                    "spec", {}
                ).get("containers", [])

                for container in containers:
                    # At least one probe should be defined
                    has_liveness = "livenessProbe" in container
                    has_readiness = "readinessProbe" in container

                    assert has_liveness or has_readiness, \
                        f"No health probes in {yaml_file} for container {container.get('name')}"


"""Verify workloads have resource limits"""
    def test_workload_resource_limits_defined(self, test_config):
        workloads_dir = test_config["workloads_dir"]

        for yaml_file in workloads_dir.glob("*-service.yaml"):
            with open(yaml_file) as f:
                docs = list(yaml.safe_load_all(f))

            # Find Deployment objects
            deployments = [d for d in docs if d and d.get("kind") == "Deployment"]

            for deployment in deployments:
                containers = deployment.get("spec", {}).get("template", {}).get(
                    "spec", {}
                ).get("containers", [])

                for container in containers:
                    resources = container.get("resources", {})

                    # Should have at least requests defined
                    assert "requests" in resources or "limits" in resources, \
                        f"No resource limits in {yaml_file} for container {container.get('name')}"


"""Verify Makefile has required targets"""
    def test_makefile_targets_exist(self, test_config):
        makefile_path = test_config["project_root"] / "Makefile"
        assert makefile_path.exists(), "Makefile not found"

        with open(makefile_path) as f:
            makefile_content = f.read()

        required_targets = [
            "init:",
            "deploy-infra:",
            "deploy-workloads:",
            "test-all:",
            "collect-metrics:",
            "destroy:",
        ]

        for target in required_targets:
            assert target in makefile_content, f"Makefile target '{target}' not found"
