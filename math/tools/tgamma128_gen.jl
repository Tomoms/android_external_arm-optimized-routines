# -*- julia -*-
#
# Generate tgamma128.h, containing polynomials and constants used by
# tgamma128.c.
#
# Copyright (c) 2006,2009,2023 Arm Limited.
# SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception

# This Julia program depends on the 'Remez' and 'SpecialFunctions'
# library packages. To install them, run this at the interactive Julia
# prompt:
#
#   import Pkg; Pkg.add(["Remez", "SpecialFunctions"])
#
# Tested on Julia 1.4.1 (Ubuntu 20.04) and 1.9.0 (22.04).

import Printf
import Remez
import SpecialFunctions

# Round a BigFloat to 128-bit long double and format it as a C99 hex
# float literal.
function quadhex(x)
    sign = " "
    if x < 0
        sign = "-"
        x = -x
    end

    exponent = BigInt(floor(log2(x)))
    exponent = max(exponent, -16382)
    @assert(exponent <= 16383) # else overflow

    x /= BigFloat(2)^exponent
    @assert(1 <= x < 2)
    x *= BigFloat(2)^112
    mantissa = BigInt(round(x))

    mantstr = string(mantissa, base=16, pad=29)
    return Printf.@sprintf("%s0x%s.%sp%+dL", sign, mantstr[1], mantstr[2:end],
                           exponent)
end

# Round a BigFloat to 128-bit long double and return it still as a
# BigFloat.
function quadval(x, round=0)
    sign = +1
    if x.sign < 0
        sign = -1
        x = -x
    end

    exponent = BigInt(floor(log2(x)))
    exponent = max(exponent, -16382)
    @assert(exponent <= 16383) # else overflow

    x /= BigFloat(2)^exponent
    @assert(1 <= x < 2)
    x *= BigFloat(2)^112
    if round < 0
        mantissa = floor(x)
    elseif round > 0
        mantissa = ceil(x)
    else
        mantissa = round(x)
    end

    return sign * mantissa * BigFloat(2)^(exponent - 112)
end

# Output an array of BigFloats as a C array declaration.
function dumparray(a, name)
    println("static const long double ", name, "[] = {")
    for x in N
        println("    ", quadhex(x), ",")
    end
    println("};")
end

print("/*
 * Polynomial coefficients and other constants for tgamma128.c.
 *
 * Copyright (c) 2006,2009,2023 Arm Limited.
 * SPDX-License-Identifier: MIT OR Apache-2.0 WITH LLVM-exception
 */
")

Base.MPFR.setprecision(512)

e = exp(BigFloat(1))

print("
/* The largest positive value for which 128-bit tgamma does not overflow. */
")
lo = BigFloat("1000")
hi = BigFloat("2000")
while true
    global lo
    global hi
    global max_x

    mid = (lo + hi) / 2
    if mid == lo || mid == hi
        max_x = mid
        break
    end
    if SpecialFunctions.logabsgamma(mid)[1] < 16384 * log(BigFloat(2))
        lo = mid
    else
        hi = mid
    end
end
max_x = quadval(max_x, -1)
println("static const long double max_x = ", quadhex(max_x), ";")

print("
/* Coefficients of the polynomial used in the tgamma_large() subroutine */
")
N, D, E, X = Remez.ratfn_minimax(
    x -> x==0 ? sqrt(BigFloat(2)*pi/e) :
                exp(SpecialFunctions.logabsgamma(1/x)[1] +
                    (1/x-0.5)*(1+log(x))),
    (0, 1/BigFloat(8)),
    24, 0,
    (x, y) -> 1/y
)
dumparray(N, "coeffs_large")

print("
/* Coefficients of the polynomial used in the tgamma_tiny() subroutine */
")
N, D, E, X = Remez.ratfn_minimax(
    x -> x==0 ? 1 : 1/(x*SpecialFunctions.gamma(x)),
    (0, 1/BigFloat(32)),
    13, 0,
)
dumparray(N, "coeffs_tiny")

print("
/* The location within the interval [1,2] where gamma has a minimum.
 * Specified as the sum of two 128-bit values, for extra precision. */
")
lo = BigFloat("1.4")
hi = BigFloat("1.5")
while true
    global lo
    global hi
    global min_x

    mid = (lo + hi) / 2
    if mid == lo || mid == hi
        min_x = mid
        break
    end
    if SpecialFunctions.digamma(mid) < 0
        lo = mid
    else
        hi = mid
    end
end
min_x_hi = quadval(min_x, -1)
println("static const long double min_x_hi = ", quadhex(min_x_hi), ";")
println("static const long double min_x_lo = ", quadhex(min_x - min_x_hi), ";")

print("
/* The actual minimum value that gamma takes at that location.
 * Again specified as the sum of two 128-bit values. */
")
min_y = SpecialFunctions.gamma(min_x)
min_y_hi = quadval(min_y, -1)
println("static const long double min_y_hi = ", quadhex(min_y_hi), ";")
println("static const long double min_y_lo = ", quadhex(min_y - min_y_hi), ";")

function taylor_bodge(x)
    # Taylor series generated by Wolfram Alpha for (gamma(min_x+x)-min_y)/x^2.
    # Used in the Remez calls below for x values very near the origin, to avoid
    # significance loss problems when trying to compute it directly via that
    # formula (even in MPFR's extra precision).
    return BigFloat("0.428486815855585429730209907810650582960483696962660010556335457558784421896667728014324097132413696263704801646004585959298743677879606168187061990204432200")+x*(-BigFloat("0.130704158939785761928008749242671025181542078105370084716141350308119418619652583986015464395882363802104154017741656168641240436089858504560718773026275797")+x*(BigFloat("0.160890753325112844190519489594363387594505844658437718135952967735294789599989664428071656484587979507034160383271974554122934842441540146372016567834062876")+x*(-BigFloat("0.092277030213334350126864106458600575084335085690780082222880945224248438672595248111704471182201673989215223667543694847795410779036800385804729955729659506"))))
end

print("
/* Coefficients of the polynomial used in the tgamma_central() subroutine
 * for computing gamma on the interval [1,min_x] */
")
N, D, E, X = Remez.ratfn_minimax(
    x -> x < BigFloat(0x1p-64) ? taylor_bodge(-x) :
        (SpecialFunctions.gamma(min_x - x) - min_y) / (x*x),
    (0, min_x - 1),
    31, 0,
    (x, y) -> x^2,
)
dumparray(N, "coeffs_central_neg")

print("
/* Coefficients of the polynomial used in the tgamma_central() subroutine
 * for computing gamma on the interval [min_x,2] */
")
N, D, E, X = Remez.ratfn_minimax(
    x -> x < BigFloat(0x1p-64) ? taylor_bodge(x) :
        (SpecialFunctions.gamma(min_x + x) - min_y) / (x*x),
    (0, 2 - min_x),
    28, 0,
    (x, y) -> x^2,
)
dumparray(N, "coeffs_central_pos")

print("
/* 128-bit float value of pi, used by the sin_pi_x_over_pi subroutine
 */
")
println("static const long double pi = ", quadhex(BigFloat(pi)), ";")
