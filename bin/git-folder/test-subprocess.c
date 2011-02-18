#include "cache.h"
#include "run-command.h"

int main(int argc, char **argv)
{
	const char *prefix;
	struct child_process cp;
	int nogit = 0;

	prefix = setup_git_directory_gently(&nogit);
	if (nogit)
		die("No git repo found");
	if (!strcmp(argv[1], "--setup-work-tree")) {
		setup_work_tree();
		argv++;
	}
	memset(&cp, 0, sizeof(cp));
	cp.git_cmd = 1;
	cp.argv = (const char **)argv+1;
	return run_command(&cp);
}
