# Privacy notice

Arduino Q Board Shell Wizard runs local host launchers and board scripts. The tool has no publisher-operated service or telemetry. It does not send provisioning requests, passwords, board identities, or SSH keys to the repository publisher.

The host transfers board scripts over USB/ADB and sends a protected unattended request through stdin. The board uses the requested settings, including passwords when supplied, to configure its own account and network connections. The request is not uploaded as a file. The host launcher removes its temporary board script directory after execution and reports cleanup failures.

Keep request files and generated credentials in protected local storage outside application repositories, wizard installations, and plugin caches. The tool does not delete those credential sources. Its result JSON reports stages and actions without credentials. Follow the [private request rules](unattended.md#prepare-and-use-a-private-request-file); never paste passwords or request contents into chat or support issues.

Optional SSH integration installs the selected public key on the board and updates a marked alias in the host SSH config, applying the documented [directory/config protections](technical.md#ssh-client-integration). Private keys are not supplied to the board tool.

Your agent provider, plugin marketplace, secret manager, operating system, and network services have their own storage and privacy practices. This notice describes the wizard's behavior; installing its skill does not change those providers' policies or execution permissions.

For questions, use the [repository issue tracker](https://github.com/manchoz/arduino-board-shell-wizard/issues) with nonsecret details. Software reuse terms are in the [MPL-2.0 license](../LICENSE).
