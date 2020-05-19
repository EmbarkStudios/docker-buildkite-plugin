$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function is_enabled {
    $val = if ($args[0]) { $args[0] } else { $args[1] }
    @("true", "on", "1").Contains($val)
}

$debug_mode = if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_DEBUG "off") {
    # Use Write-Host here since echo is apparently an alias for Write-Output which introduces
    # the string as a return value to the function which is really weird, but whatever
    Write-Host "--- :bug: Enabling debug mode"
    $true
}
else { $false }

if ($env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE -or $env:BUILDKITE_PLUGIN_DOCKER_CTX) {
    $build_args = @("-t", $env:BUILDKITE_PLUGIN_DOCKER_IMAGE)

    if ($env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE) {
        $build_args += @("-f", $env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE)
    }

    $build_args += if ($env:BUILDKITE_PLUGIN_DOCKER_CTX) { $env:BUILDKITE_PLUGIN_DOCKER_CTX } else { "." }

    Write-Host "--- :docker: Building :hammer: '$env:BUILDKITE_PLUGIN_DOCKER_IMAGE'"

    if ($debug_mode) {
        Write-Host "executing 'docker build $build_args' in $(Get-Location)"
    }

    docker.exe build $build_args

    if ($LastExitCode -ne 0) {
        Write-Host "--- :docker: :hurtrealbad: Failed :hammer: $env:BUILDKITE_PLUGIN_DOCKER_IMAGE!"
        exit $LastExitCode
    }
    else {
        Write-Host "--- :docker: :metal: Finished :hammer: $env:BUILDKITE_PLUGIN_DOCKER_IMAGE successfully!"
    }
}

$docker_args = @()

# Windows doesn't support TTY well, shocking!
$docker_args += "-i"
# Remove the container when it finishes
$docker_args += "--rm"

if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_MOUNT_CHECKOUT "on") {
    $work_dir = if ($env:BUILDKITE_PLUGIN_DOCKER_WORKDIR) { $env:BUILDKITE_PLUGIN_DOCKER_WORKDIR } else { "c:/workdir" }
    $docker_args += @("--volume", "$(Get-Location):$work_dir")
    $docker_args += @("--workdir", $work_dir)
}

if ($env:BUILDKITE_PLUGIN_DOCKER_USER) {
    $docker_args += @("-u", $env:BUILDKITE_PLUGIN_DOCKER_USER)
}

if ($env:BUILDKITE_PLUGIN_DOCKER_ENTRYPOINT) {
    $docker_args += @("--entrypoint", $env:BUILDKITE_PLUGIN_DOCKER_ENTRYPOINT)
}

if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_PROPAGATE_ENVIRONMENT "off") {
    if ($env:BUILDKITE_ENV_FILE) {
        # Read in the env file and convert to --env params for docker
        # This is because --env-file doesn't support newlines or quotes per https://docs.docker.com/compose/env-file/#syntax-rules
        foreach ($line in Get-Content "$env:BUILDKITE_ENV_FILE") {
            $docker_args += @("--env", $line)
        }
    }
    else {
        Write-Host "🚨 Not propagating environment variables to container as $env:BUILDKITE_ENV_FILE is not set"
    }
}

$cmd = @()

if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_MOUNT_BUILDKITE_AGENT "on") {
    # Get the path to the agent executable's directory on our host
    $bk_dir = Get-ChildItem buildkite-agent | Select-Object -exp Definition | split-path -Parent

    # We can't actually mount only the agent binary in Windows https://github.com/moby/moby/issues/30555
    # so instead we mount the directory as ro and emit a command to update the PATH before
    # executing any other commands
    $cmd += @("mklink", "c:`\windows`\system32`\buildkite-agent.exe", "c:`\bk-agent`\buildkite-agent.exe", " && ")
    $docker_args += @("--volume", "${bk_dir}:c:/bk-agent:ro")
}

$docker_args += $env:BUILDKITE_PLUGIN_DOCKER_IMAGE

$cmds = if ($env:BUILDKITE_PLUGIN_DOCKER_COMMAND -and $env:BUILDKITE_COMMAND) {
    Write-Host "+++ Error: Can't use both a step level command and the command parameter of the plugin"
    exit 1
}
elseif ($env:BUILDKITE_COMMAND) {
    $env:BUILDKITE_COMMAND
}
else {
    $env:BUILDKITE_PLUGIN_DOCKER_COMMAND
}

$prelude = @("cmd.exe", "/C")

$docker_args += $prelude
$display_cmd += $prelude

$cmd += $cmds -replace "`n", " && "

$docker_args += "$cmd"
$display_cmd += "$cmd"

Write-Host "--- :docker: Running '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE"

if ($debug_mode) {
    Write-Host "executing 'docker run $docker_args'"
}

docker.exe run $docker_args

if ($LastExitCode -ne 0) {
    Write-Host "--- :docker: :hurtrealbad: Failed '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE!"
    exit $LastExitCode
}
else {
    Write-Host "--- :docker: :metal: Finished '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE successfully!"
    exit 0
}
