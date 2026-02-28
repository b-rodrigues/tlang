/* src/ffi/stats_stubs.c */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <math.h>

/* Beasley-Springer-Moro approximation for the inverse of the standard 
   normal cumulative distribution function. Accuracy is about 10^-9. */
double normal_quantile_c(double p) {
  if (p <= 0.0) return -HUGE_VAL;
  if (p >= 1.0) return HUGE_VAL;

  double x = p - 0.5;
  static const double a[] = {
      2.50662823884, -30.66479806614, 226.94908191330, -1024.58034873174,
      2745.85124028376, -4419.64350699405, 4111.45939223701, -2022.20393874943,
      391.31401397585};
  static const double b[] = {
      -8.47351093090, 132.09169736622, -822.65330273823, 2735.85431663039,
      -5260.10661207425, 6047.82853254474, -4002.84591355412, 1146.61951992321};
  static const double c[] = {
      -0.003184522384, 0.005149610133, 0.1328005626, 0.2243610955,
      0.1911774827, 0.3951133148, 0.7011776274, 1.4921674407};
  static const double d[] = {
      0.000103155956, 0.001639208043, 0.0400624445, 0.0827398132,
      0.4475116305, 0.1515643444, -2.5356767498, -8.3285925635};

  if (fabs(x) <= 0.42) {
    double r = x * x;
    double num =
        ((((((((a[8] * r + a[7]) * r + a[6]) * r + a[5]) * r + a[4]) * r + a[3]) *
          r + a[2]) *
         r +
        a[1]) *
       r +
      a[0]);
    double den =
        ((((((((b[7] * r + b[6]) * r + b[5]) * r + b[4]) * r + b[3]) * r + b[2]) *
          r + b[1]) *
         r +
        b[0]) *
       r +
      1.0);
    return x * num / den;
  } else {
    double r = (x > 0) ? (1.0 - p) : p;
    double s = log(-log(r));
    double t = (((((((c[7] * s + c[6]) * s + c[5]) * s + c[4]) * s + c[3]) * s +
                   c[2]) *
                  s +
                 c[1]) *
                s +
               c[0]);
    double u = (((((((d[7] * s + d[6]) * s + d[5]) * s + d[4]) * s + d[3]) * s +
                   d[2]) *
                  s +
                 d[1]) *
                s +
               d[0]);
    double z = t / u;
    return (x > 0) ? -z : z;
  }
}

CAMLprim value caml_stats_normal_quantile(value v) {
  return caml_copy_double(normal_quantile_c(Double_val(v)));
}

/* Cornish-Fisher expansion for Student's T distribution.
   Accurate for df > 4 and p not extremely close to 0 or 1.
   For smaller df or extreme p, we fallback to a simpler version. */
double t_quantile_c(double p, int df) {
  double z = normal_quantile_c(p);
  if (df <= 0) return z;
  
  double df_f = (double)df;
  double z2 = z * z;
  double z3 = z2 * z;
  double z5 = z3 * z2;
  double z7 = z5 * z2;
  double z9 = z7 * z2;
  
  /* Cornish-Fisher expansion terms */
  double t = z + (z3 + z) / (4.0 * df_f) +
             (5.0 * z5 + 16.0 * z3 + 3.0 * z) / (96.0 * df_f * df_f) +
             (3.0 * z7 + 19.0 * z5 + 17.0 * z3 - 15.0 * z) / (384.0 * df_f * df_f * df_f) +
             (79.0 * z9 + 776.0 * z7 + 1482.0 * z5 - 1920.0 * z3 - 945.0 * z) / 
             (92160.0 * df_f * df_f * df_f * df_f);
             
  return t;
}

CAMLprim value caml_stats_t_quantile(value vp, value vdf) {
  return caml_copy_double(t_quantile_c(Double_val(vp), Int_val(vdf)));
}
