# Docker Development Environment

Dockerfile defines the local, lock-pinned Ubuntu 22.04 development image for
the open-source retroSoC regression flows. It owns the container runtime and
tool bootstrap only; locked RTL, PDK, and application sources remain in the
mounted checkout and are installed with the setup-regression Make target.

Build the image from the repository root, then use the commands in the root
README. Validate Docker changes with an image build, the doctor target, and the
Icarus assembly smoke flow inside the container.
