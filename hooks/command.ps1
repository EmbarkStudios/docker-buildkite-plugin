$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function is_enabled {
    $val = if ($args[0]) { $args[0] } else { $args[1] }
    @("true","on","1").Contains($val)
}

$debug_mode = if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_DEBUG "off") {
    # Use Write-Host here since echo is apparently an alias for Write-Output which introduces
    # the string as a return value to the function which is really weird, but whatever
    Write-Host "--- :bug: Enabling debug mode"
    $true
} else { $false }

if ($env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE -or $env:BUILDKITE_PLUGIN_DOCKER_CTX) {
    $build_args = @("-t", $env:BUILDKITE_PLUGIN_DOCKER_IMAGE)

    if ($env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE) {
        $build_args += @("-f", $env:BUILDKITE_PLUGIN_DOCKER_DOCKER_FILE)
    }

    $build_args += if ($env:BUILDKITE_PLUGIN_DOCKER_CTX) { $env:BUILDKITE_PLUGIN_DOCKER_CTX } else { "." }

    echo "--- :docker: Building :hammer: '$env:BUILDKITE_PLUGIN_DOCKER_IMAGE'"

    if ($debug_mode) {
        echo "executing 'docker build $build_args' in $(Get-Location)"
    }

    docker.exe build $build_args

    if ($LastExitCode -ne 0) {
        echo "--- :docker: :hurtrealbad: Failed :hammer: $env:BUILDKITE_PLUGIN_DOCKER_IMAGE!"
        exit $LastExitCode
    } else {
        echo "--- :docker: :metal: Finished :hammer: $env:BUILDKITE_PLUGIN_DOCKER_IMAGE successfully!"
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

# TODO: Mount other volumes

if ($env:BUILDKITE_PLUGIN_DOCKER_USER) {
    $docker_args += @("-u", $env:BUILDKITE_PLUGIN_DOCKER_USER)
}

if ($env:BUILDKITE_PLUGIN_DOCKER_ENTRYPOINT) {
    $docker_args += @("--entrypoint", $env:BUILDKITE_PLUGIN_DOCKER_ENTRYPOINT)
}

if (is_enabled $env:BUILDKITE_PLUGIN_DOCKER_MOUNT_BUILDKITE_AGENT "on") {
    # Get the path to the agent executable on our host
    $bk_agent = gcm buildkite-agent | select -ExpandProperty Definition

    # Pass the current environment vars needed for the agent to function correctly inside the container
    $docker_args += @("--env", "BUILDKITE_JOB_ID", "--env", "BUILDKITE_BUILD_ID", "--env", "BUILDKITE_AGENT_ACCESS_TOKEN")
    # Mount the agent so it can be used inside the container
    $docker_args += @("--volume", "${bk_agent}:c:/windows/system32/buildkite-agent.exe")
}

$docker_args += $env:BUILDKITE_PLUGIN_DOCKER_IMAGE

$cmds = if ($env:BUILDKITE_PLUGIN_DOCKER_COMMAND -and $env:BUILDKITE_COMMAND) {
    echo "+++ Error: Can't use both a step level command and the command parameter of the plugin"
    exit 1
} elseif ($env:BUILDKITE_COMMAND) {
    $env:BUILDKITE_COMMAND
} else {
    $env:BUILDKITE_PLUGIN_DOCKER_COMMAND
}

$docker_args += @("cmd.exe", "/C")
$display_cmd = @("cmd.exe", "/C")

$cmds = $cmds -replace "`n", " && "

$docker_args += $cmds
$display_cmd += $cmds

echo "--- :docker: Running '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE"

if ($debug_mode) {
    echo "executing 'docker run $docker_args'"
}

docker.exe run $docker_args

if ($LastExitCode -ne 0) {
    echo "--- :docker: :hurtrealbad: Failed '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE!"
    exit $LastExitCode
} else {
    echo "--- :docker: :metal: Finished '$display_cmd' in $env:BUILDKITE_PLUGIN_DOCKER_IMAGE successfully!"
    exit 0
}
