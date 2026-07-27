#include <assert.h>
#include <stdio.h>

#include "calc_core.h"

int main(void)
{
    unsigned char error;

    assert(calc_binary(125, 275, '+', &error) == 400 && error == CALC_OK);
    assert(calc_binary(500, 725, '-', &error) == -225 && error == CALC_OK);
    assert(calc_binary(150, 200, '*', &error) == 300 && error == CALC_OK);
    assert(calc_binary(-150, 200, '*', &error) == -300 && error == CALC_OK);
    assert(calc_binary(750, 250, '/', &error) == 300 && error == CALC_OK);
    calc_binary(100, 0, '/', &error);
    assert(error == CALC_ERR_DIV_ZERO);
    calc_binary(CALC_MAX, 200, '*', &error);
    assert(error == CALC_ERR_OVERFLOW);
    assert(calc_binary(CALC_MAX, 100, '*', &error) == CALC_MAX);
    assert(calc_square_root(400, &error) == 200 && error == CALC_OK);
    assert(calc_square_root(200, &error) == 141 && error == CALC_OK);
    calc_square_root(-100, &error);
    assert(error == CALC_ERR_NEG_ROOT);

    puts("calculator arithmetic tests passed");
    return 0;
}
