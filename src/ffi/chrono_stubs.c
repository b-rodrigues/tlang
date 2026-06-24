/* src/ffi/chrono_stubs.c                                       */
/* C FFI stubs for the chrono package.                          */
/*                                                              */
/* Provides caml_tz_offset: computes the UTC offset (in seconds */
/* EAST of UTC) for a given UNIX microsecond timestamp and IANA */
/* timezone name using POSIX localtime_r with TZ= override.     */
/*                                                              */
/* THREAD-SAFETY NOTE: setenv/tzset/localtime_r operate on      */
/* global process state (the TZ environment variable and         */
/* tzset()'s internal cache). This is safe under OCaml 4.x      */
/* (single-domain runtime — the equivalent of the GIL holds     */
/* the runtime lock across C stubs). If the runtime is ever      */
/* upgraded to OCaml 5 with multiple Domains calling this        */
/* simultaneously, a data race will occur. Revisit this          */
/* function before enabling multicore.                          */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <time.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

static int find_zoneinfo_path(const char *tz_name, char *out, size_t out_size)
{
  /* Probe order: TZDIR env var, then known platform paths. */
  static const char *candidates[] = {
    NULL,                    /* slot 0 = TZDIR env var (filled at runtime) */
    "/etc/zoneinfo",         /* Nix */
    "/usr/share/zoneinfo",   /* standard Linux */
    "/usr/lib/zoneinfo",     /* macOS / non-Nix Linux */
  };
  static const int n_candidates = sizeof(candidates) / sizeof(candidates[0]);

  size_t name_len = strlen(tz_name);

  for (int i = 0; i < n_candidates; i++) {
    const char *dir;
    if (i == 0) {
      dir = getenv("TZDIR");
      if (!dir) continue;
    } else {
      dir = candidates[i];
    }

    size_t dir_len = strlen(dir);
    /* path = dir / tz_name + NUL */
    size_t path_len = dir_len + 1 + name_len + 1;
    if (path_len > out_size) continue;

    if (access(dir, R_OK) != 0) continue;

    memcpy(out, dir, dir_len);
    out[dir_len] = '/';
    memcpy(out + dir_len + 1, tz_name, name_len + 1);

    if (access(out, R_OK) == 0) return 0;
  }

  return -1;
}

CAMLprim value caml_tz_offset(value v_micros, value v_tz_name)
{
  CAMLparam2(v_micros, v_tz_name);

  int64_t micros = Int64_val(v_micros);

  /* Extract tz_name immediately — String_val returns a pointer
     into the OCaml heap; any subsequent allocation
     (malloc, setenv, etc.) could trigger GC compaction. */
  const char *tz_name_raw = String_val(v_tz_name);

  /* Resolve the full zoneinfo path for this tz_name. */
  char zone_path[512];
  if (find_zoneinfo_path(tz_name_raw, zone_path, sizeof(zone_path)) != 0) {
    char err_msg[1024];
    snprintf(err_msg, sizeof(err_msg),
      "caml_tz_offset: cannot find zoneinfo file for '%s' "
      "(searched: TZDIR, /etc/zoneinfo, /usr/share/zoneinfo, "
      "/usr/lib/zoneinfo)",
      tz_name_raw);
    caml_failwith(err_msg);
  }

  size_t zone_path_len = strlen(zone_path);
  /* TZ value = ":" + zone_path + NUL */
  char *tz_buf = (char *)malloc(zone_path_len + 2);
  tz_buf[0] = ':';
  memcpy(tz_buf + 1, zone_path, zone_path_len + 1);

  /* Save TZ before changing it — getenv returns a pointer into
     environ which setenv invalidates, so strdup immediately. */
  char *orig_tz = getenv("TZ");
  char *saved_tz = orig_tz ? strdup(orig_tz) : NULL;

  setenv("TZ", tz_buf, 1);
  free(tz_buf);
  tzset();

  /* Floor division for negative timestamps (pre-1970) */
  int64_t secs = micros >= 0
    ? micros / 1000000
    : (micros - 999999) / 1000000;

  time_t t = (time_t)secs;
  struct tm tm;
  localtime_r(&t, &tm);
  int64_t offset_sec = (int64_t)tm.tm_gmtoff;

  /* Restore original TZ */
  if (saved_tz) {
    setenv("TZ", saved_tz, 1);
    free(saved_tz);
  } else {
    unsetenv("TZ");
  }
  tzset();

  CAMLlocal1(result);
  result = caml_copy_int64(offset_sec);
  CAMLreturn(result);
}
