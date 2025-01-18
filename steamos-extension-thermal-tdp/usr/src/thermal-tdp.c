#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdbool.h>
#include <time.h>
#include <errno.h>

typedef struct {
	unsigned int temp;
	unsigned int tdp;
} entry;

// Stolen from: https://stackoverflow.com/questions/1157209/is-there-an-alternative-sleep-function-in-c-to-milliseconds
// It is fucking ridiculous that usleep got deprecated.
void msleep(unsigned long int msec) {
    struct timespec ts;
    int res;

    ts.tv_sec = msec / 1000;
    ts.tv_nsec = (msec % 1000) * 1000000;

    do {
        res = nanosleep(&ts, &ts);
    } while (res && errno == EINTR);
}

unsigned int tdp_bsearch(
		const unsigned int base,
		const unsigned int temp, 
		const entry *const entries, 
		const unsigned int length
) {
	if (temp < entries[0].temp)
		return base;

	else if (temp >= entries[length - 1].temp)
		return entries[length - 1].tdp;

	else if (temp >= entries[length / 2 - 1].temp && temp < entries[length / 2].temp)
		return entries[length / 2 - 1].tdp;

	else if (temp < entries[length / 2 - 1].temp)
		return tdp_bsearch(base, temp, entries, length / 2 - 1);
	else
		return tdp_bsearch(entries[length / 2 - 1].tdp, temp, &entries[length / 2], length - (length / 2));
}

const char THERMAL_ZONE_TEMP[] = "/sys/devices/virtual/thermal/thermal_zone0/temp";

bool read_uint(const char *const restrict filename, unsigned int *const output) {
	FILE *file = fopen(filename, "rb");
	if (!file)
		return false;
	
	if (1 != fscanf(file, "%u", output)) {
		fclose(file);
		return false;
	}

	if (0 != fclose(file))
		return false;

	return true;
}

int main(const int argc, char *const *const argv) {

	if (4 > argc)
		return 1;

	unsigned int ms, base;
	if (1 != sscanf(argv[1], "%u", &ms))
		return 1;
	if (1 != sscanf(argv[2], "%u", &base))
		return 1;
	base *= 1000000;

	entry *entries = malloc(sizeof(entry) * (argc - 2));
	if (!entries)
		return 5;

	for (int i = 3; i < argc; ++i) {
		if (2 != sscanf(argv[i], "%u:%u", &entries[i - 3].temp, &entries[i - 3].tdp)) {
			free(entries);
			return 1;
		}
		entries[i - 3].temp *= 1000;
		entries[i - 3].tdp *= 1000000;
	}

	char power1_cap[75];
	char power2_cap[75];
	unsigned int hwmon_id = 0;
	do {
		snprintf(
			(char *) &power1_cap, 
			sizeof(power1_cap) / sizeof(char), 
			"/sys/devices/pci0000:00/0000:00:08.1/0000:04:00.0/hwmon/hwmon%d/power1_cap", ++hwmon_id
		);
	} while (0 != access(power1_cap, F_OK));

	snprintf(
		(char *) &power2_cap, 
		sizeof(power2_cap) / sizeof(char), 
		"/sys/devices/pci0000:00/0000:00:08.1/0000:04:00.0/hwmon/hwmon%u/power2_cap", hwmon_id
	);

	while(true) {
		unsigned int temp;
		if (!read_uint(THERMAL_ZONE_TEMP, &temp))
			return 2;

		unsigned int tdp = tdp_bsearch(base, temp, entries, argc - 3);

		const char *caps[] = {power1_cap, power2_cap};
		for (unsigned int cap_id = 0; cap_id < 2; ++cap_id) {
			unsigned int current;
			if (!read_uint(caps[cap_id], &current))
				return 2;

			if (current != tdp) {
				FILE *cap = fopen(caps[cap_id], "wb");
				if (!cap)
					return 3;
				if (0 > fprintf(cap, "%u\n", tdp)) {
					fclose(cap);
					return 3;
				}
				fclose(cap);
			}
		}
		msleep(ms);
	}
}
