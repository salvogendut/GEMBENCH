#ifndef CALC_CORE_H
#define CALC_CORE_H

#define CALC_SCALE         100L
#define CALC_MAX           20000000L
#define CALC_PRODUCT_LIMIT 2000000000UL

#define CALC_OK            0
#define CALC_ERR_DIV_ZERO  1
#define CALC_ERR_OVERFLOW  2
#define CALC_ERR_NEG_ROOT  3

static unsigned long calc_magnitude(long value)
{
    return value < 0 ? (unsigned long)(-value) : (unsigned long)value;
}

static long calc_binary(long left, long right, unsigned char op,
                        unsigned char *error)
{
    unsigned long lm = calc_magnitude(left);
    unsigned long rm = calc_magnitude(right);
    long result;

    *error = CALC_OK;
    if (op == '+') result = left + right;
    else if (op == '-') result = left - right;
    else if (op == '*') {
        if (rm && lm > CALC_PRODUCT_LIMIT / rm) {
            *error = CALC_ERR_OVERFLOW;
            return 0;
        }
        result = (left * right) / CALC_SCALE;
    } else {
        if (!right) {
            *error = CALC_ERR_DIV_ZERO;
            return 0;
        }
        result = (left * CALC_SCALE) / right;
    }
    if (calc_magnitude(result) > (unsigned long)CALC_MAX) {
        *error = CALC_ERR_OVERFLOW;
        return 0;
    }
    return result;
}

static long calc_square_root(long value, unsigned char *error)
{
    unsigned long target;
    unsigned long low = 0, high = 44721, answer = 0;

    *error = CALC_OK;
    if (value < 0) {
        *error = CALC_ERR_NEG_ROOT;
        return 0;
    }
    target = (unsigned long)value * (unsigned long)CALC_SCALE;
    while (low <= high) {
        unsigned long middle = (low + high) >> 1;
        unsigned long square = middle * middle;
        if (square <= target) {
            answer = middle;
            low = middle + 1;
        } else {
            high = middle - 1;
        }
    }
    return (long)answer;
}

#endif
