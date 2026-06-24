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

CAMLprim value caml_tz_offset(value v_micros, value v_tz_name)
{
  CAMLparam2(v_micros, v_tz_name);

  int64_t micros = Int64_val(v_micros);

  /* Extract tz_name immediately — String_val returns a pointer
     into the OCaml heap; any subsequent allocation
     (malloc, setenv, etc.) could trigger GC compaction. */
  const char *tz_name_raw = String_val(v_tz_name);
  size_t name_len = strlen(tz_name_raw);
  char *tz_buf = (char *)malloc(name_len + 2);
  snprintf(tz_buf, name_len + 2, ":%s", tz_name_raw);

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
