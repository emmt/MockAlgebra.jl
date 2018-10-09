#
# coder-test.jl -
#
# Test suite for the coder.
#
#-------------------------------------------------------------------------------
#
# This file is part of LazyAlgebra (https://github.com/emmt/LazyAlgebra.jl)
# released under the MIT "Expat" license.
#
# Copyright (c) 2017-2018 Éric Thiébaut.
#
module CoderTests

# Deal with compatibility issues.
using Compat
using Compat.Printf
using Compat.Test
@static if isdefined(Base, :axes)
    import Base: axes
    const FastRange = CartesianIndices
else
    import Base: indices
    const axes = indices
    const FastRange = CartesianRange
end
if VERSION < v"0.7.0-DEV.3563"
    # scale! not deprecated
    rmul!(A::AbstractArray, s::Number) = scale!(A, s)
    #export mul!, rmul!
elseif VERSION < v"0.7.0-DEV.3665"
    # scale! -> mul1!
    rmul!(A::AbstractArray, s::Number) = rmul1!(A, s)
else
    import LinearAlgebra: rmul!
end

include("../src/coder.jl")
import .Coder

#------------------------------------------------------------------------------
# SIMPLE SUM

# This version is basic (no SIMD and bound checking).
gensum1(x) = gensum1(typeof(x))
gensum1(::Type{T}) where {T} = error("unsupported argument type $T")
gensum1(::Type{<:AbstractArray{T,N}}) where {T,N} =
    Coder.encode(
        :(s = zero(T)),
        :(n = length(x)),
        :for, :(i = 1:n), # use "=" here
        (
            :(s += x[i]),
        ),
        :(return s)
    )
@generated sum1(x::AbstractArray{T,N}) where {T,N} = gensum1(x)

# This version is similar to above but keyword "in" is used instead of "=".
gensum2(x) = gensum2(typeof(x))
gensum2(::Type{T}) where {T} = error("unsupported argument type $T")
gensum2(::Type{<:AbstractArray{T,N}}) where {T,N} =
    Coder.encode(
        :(s = zero(T)),
        :(n = length(x)),
        :for, :(i in 1:n), # use "in" here
        (
            :(s += x[i]),
        ),
        :(return s)
    )
@generated sum2(x::AbstractArray{T,N}) where {T,N} = gensum2(x)

# This version is without bound checking and without SIMD.
gensum3(x) = gensum3(typeof(x))
gensum3(::Type{T}) where {T} = error("unsupported argument type $T")
gensum3(::Type{<:AbstractArray{T,N}}) where {T,N} =
    Coder.encode(
        :(s = zero(T)),
        :(n = length(x)),
        :inbounds,
        (
            :for, :(i in 1:n),
            (
                :(s += x[i]),
            )
        ),
        :(return s)
    )
@generated sum3(x::AbstractArray{T,N}) where {T,N} = gensum3(x)

# This version is without bound checking and with SIMD.
gensum4(x) = gensum4(typeof(x))
gensum4(::Type{T}) where {T} = error("unsupported argument type $T")
gensum4(::Type{<:AbstractArray{T,N}}) where {T,N} =
    Coder.encode(
        :(s = zero(T)),
        :(n = length(x)),
        :inbounds,
        (
            :simd_for, :(i in 1:n),
            (
                :(s += x[i]),
            )
        ),
        :(return s)
    )
@generated sum4(x::AbstractArray{T,N}) where {T,N} = gensum4(x)

#------------------------------------------------------------------------------
# AXPBY

# Reference version.
function axpby!(a::Real, x::AbstractArray{Tx,N},
                b::Real, y::AbstractArray{Ty,N}) where {Tx<:Real,Ty<:Real,N}
    # Consider the minal number of alternatives, just to avoid dealing with
    # undefined contents.
    @assert axes(x) == axes(y)
    if a == 0 && b == 0
        fill!(y, 0)
    elseif a == 0
        rmul!(y, b)
    elseif b == 0
        @inbounds for i in eachindex(x, y)
            y[i] = a*x[i]
        end
    else
        @inbounds for i in eachindex(x, y)
            y[i] = a*x[i] + b*y[i]
        end
    end
    return y
end

# This version is the same as the reference one (results should be exactly the
# same).
@generated function axpby1!(a::Real, x::AbstractArray{Tx,N},
                            b::Real, y::AbstractArray{Ty,N}
                            ) where {Tx<:Real,Ty<:Real,N}
    Coder.encode(
        :(@assert axes(x) == axes(y)),
        :if, :(a == 0 && b == 0),
        (
            :(fill!(y, 0)),
        ),
        :elseif, :(a == 0),
        (
            :(rmul!(y, b))
        ),
        :elseif, :(b == 0),
        (
            :inbounds,
            (
                :for, :(i in eachindex(x, y)),
                (
                    :(y[i] = a*x[i])
                )
            )
        ),
        :else,
        (
            :inbounds,
            (
                :for, :(i in eachindex(x, y)),
                (
                    :(y[i] = a*x[i] + b*y[i])
                )
            )
        ),
        :(return y)
    )
end

# This one is much more complex (to check if/elseif/else).
@generated function axpby2!(a::Real, x::AbstractArray{Tx,N},
                            b::Real, y::AbstractArray{Ty,N}
                            ) where {Tx<:Real,Ty<:Real,N}
    Coder.encode(
        :(@assert axes(x) == axes(y)),
        :inbounds,
        (
            :if, :(a == 0),
            (
                :if, :(b == 0),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = 0),
                    ),
                ),
                :elseif, :(b == 1),
                (
                    # nothing to do
                ),
                :elseif, :(b == -1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = -y[i]),
                    ),
                ),
                :else,
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] *= b),
                    ),
                ),
            ),
            :elseif, :(a == 1),
            (
                :if, :(b == 0),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = x[i]),
                    ),
                ),
                :elseif, :(b == 1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] += x[i]),
                    ),
                ),
                :elseif, :(b == -1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = x[i] - y[i]),
                    ),
                ),
                :else,
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = x[i] + b*y[i]),
                    ),
                ),
            ),
            :elseif, :(a == -1),
            (
                :if, :(b == 0),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = -x[i]),
                    ),
                ),
                :elseif, :(b == 1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] -= x[i]),
                    ),
                ),
                :elseif, :(b == -1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = -x[i] - y[i]),
                    ),
                ),
                :else,
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = b*y[i] - x[i]),
                    ),
                ),
            ),
            :else,
            (
                :if, :(b == 0),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = a*x[i]),
                    ),
                ),
                :elseif, :(b == 1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] += a*x[i]),
                    ),
                ),
                :elseif, :(b == -1),
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = a*x[i] - y[i]),
                    ),
                ),
                :else,
                (
                    :simd_for, :(i in eachindex(x, y)),
                    (
                        :(y[i] = a*x[i] + b*y[i]),
                    ),
                ),
            ),
        ),
        :(return y),
    )
end

#------------------------------------------------------------------------------

# Generate a random vector plus a shift to make sure
# the sum is about one.
function generate_array(::Type{T}, dims) where {T}
    A = randn(T, dims)
    λ = (1 - sum(A))/length(A)
    return A .+ λ
end

const FLOATS = (Float32, Float64)
const SIZES  = ((1000,), (10,11), (4,5,6))
const ALPHAS = (-1, 0, 1, 3)
const BETAS  = (-1, 0, 1, 2)

@testset "Coder" begin
    for T in FLOATS,
        dims in SIZES
        x = generate_array(T, dims)
        y = generate_array(T, dims)

        s0 = sum(x)
        @test sum1(x) ≈ s0
        @test sum2(x) ≈ s0
        @test sum3(x) ≈ s0
        @test sum4(x) ≈ s0
        for a in ALPHAS, b in BETAS
            y0 = axpby!(a, x, b, copy(y))
            y1 = axpby1!(a, x, b, copy(y))
            y2 = axpby2!(a, x, b, copy(y))
            @test maximum(abs.(y1 .- y0)) == 0
            @test maximum(abs.(y2 .- y0)) ≤ eps(T)*4
        end
    end
end

end #module
