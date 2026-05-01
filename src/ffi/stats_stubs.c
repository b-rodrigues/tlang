/* src/ffi/stats_stubs.c */
#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <math.h>

/* Acklam's algorithm for the inverse normal CDF.
   Provides accuracy of about 10^-9. */
double normal_quantile_c(double p) {
    static const double a[6] = {
        -3.969683028665376e+01,  2.209460984245205e+02,
        -2.759285104469687e+02,  1.383577518672690e+02,
        -3.066479806614716e+01,  2.506628277459239e+00
    };
    static const double b[5] = {
        -5.447609879822406e+01,  1.615858368580409e+02,
        -1.556989798598866e+02,  6.680131188771972e+01,
        -1.328068155288572e+01
    };
    static const double c[6] = {
        -7.784894002430293e-03, -3.223964580411365e-01,
        -2.400758277161838e+00, -2.549732539343734e+00,
         4.374664141464968e+00,  2.938163982698783e+00
    };
    static const double d[4] = {
         7.784695709041462e-03,  3.224671290700398e-01,
         2.445134137142996e+00,  3.754408661907416e+00
    };

    if (p <= 0.0) return -HUGE_VAL;
    if (p >= 1.0) return HUGE_VAL;

    if (p < 0.02425) {
        double q = sqrt(-2.0 * log(p));
        return (((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
               ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1.0);
    }
    if (p > 1.0 - 0.02425) {
        double q = sqrt(-2.0 * log(1.0 - p));
        return -(((((c[0]*q+c[1])*q+c[2])*q+c[3])*q+c[4])*q+c[5]) /
                ((((d[0]*q+d[1])*q+d[2])*q+d[3])*q+1.0);
    }
    double q = p - 0.5;
    double r = q * q;
    return (((((a[0]*r+a[1])*r+a[2])*r+a[3])*r+a[4])*r+a[5])*q /
           (((((b[0]*r+b[1])*r+b[2])*r+b[3])*r+b[4])*r+1.0);
}

CAMLprim value caml_stats_normal_quantile(value v) {
    return caml_copy_double(normal_quantile_c(Double_val(v)));
}

/* Cornish-Fisher expansion for Student's T distribution.
   Accurate for df > 4 and p not extremely close to 0 or 1. */
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
