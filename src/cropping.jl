#
# cropping.jl -
#
# Provide zero-padding and cropping operators.
#
#-------------------------------------------------------------------------------
#
# This file is part of LazyAlgebra (https://github.com/emmt/LazyAlgebra.jl)
# released under the MIT "Expat" license.
#
# Copyright (c) 2019-2021, Éric Thiébaut.
#

module Cropping

# FIXME: add simplifying rules:
#   Z'*Z = Id (not Z*Z' = Id)  crop zero-padded array is identity

export
    CroppingOperator,
    ZeroPaddingOperator,
    defaultoffset

using ArrayTools
using ..Foundations
using ..LazyAlgebra
using ..LazyAlgebra: bad_argument, bad_size
import ..LazyAlgebra: apply!, vcreate,
    input_size, input_ndims, output_size, output_ndims

"""
    CroppingOperator(outdims, inpdims, offset=defaultoffset(outdims,inpdims))

yields a linear map which implements cropping of arrays of size `inpdims` to
produce arrays of size `outdims`.  By default, the output array is centered
with respect to the inpput array (using the same conventions as `fftshift`).
Optional argument `offset` can be used to specify a different relative
position.  If `offset` is given, the output value at multi-dimensional index
`i` is given by input value at index `j = i + offset`.

The adjoint of a cropping operator is a zero-padding operator.

See also: [`ZeroPaddingOperator`](@ref).

"""
struct CroppingOperator{N} <: LinearMapping
    outdims::NTuple{N,Int} # cropped dimensions
    inpdims::NTuple{N,Int} # input dimensions
    offset::CartesianIndex{N} # offset of cropped region w.r.t. input array
    function CroppingOperator{N}(outdims::NTuple{N,Int},
                                 inpdims::NTuple{N,Int}) where {N}
        @inbounds for d in 1:N
            1 ≤ outdims[d] || error("invalid output dimension(s)")
            outdims[d] ≤ inpdims[d] ||
                error(1 ≤ inpdims[d]
                      ? "invalid input dimension(s)"
                      : "output dimensions must be less or equal input ones")
        end
        offset = defaultoffset(inpdims, outdims)
        return new{N}(outdims, inpdims, offset)
    end
    function CroppingOperator{N}(outdims::NTuple{N,Int},
                                 inpdims::NTuple{N,Int},
                                 offset::CartesianIndex{N}) where {N}
        @inbounds for d in 1:N
            1 ≤ outdims[d] || error("invalid output dimension(s)")
            outdims[d] ≤ inpdims[d] ||
                error(1 ≤ inpdims[d]
                      ? "invalid input dimension(s)"
                      : "output dimensions must less or equal input ones")
            0 ≤ offset[d] ≤ inpdims[d] - outdims[d] ||
                error("out of range offset(s)")
        end
        return new{N}(outdims, inpdims, offset)
    end
end

@callable CroppingOperator

commonpart(C::CroppingOperator) = CartesianIndices(output_size(C))
offset(C::CroppingOperator) = C.offset

input_ndims(C::CroppingOperator{N}) where {N} = N
input_size(C::CroppingOperator) = C.inpdims
input_size(C::CroppingOperator, i...) = input_size(C)[i...]

output_ndims(C::CroppingOperator{N}) where {N} = N
output_size(C::CroppingOperator) = C.outdims
output_size(C::CroppingOperator, i...) = output_size(C)[i...]

# Union of acceptable types for the offset.
const Offset = Union{CartesianIndex,Integer,Tuple{Vararg{Integer}}}

CroppingOperator(outdims::ArraySize, inpdims::ArraySize) =
    CroppingOperator(to_size(outdims), to_size(inpdims))

CroppingOperator(outdims::ArraySize, inpdims::ArraySize, offset::Offset) =
    CroppingOperator(to_size(outdims), to_size(inpdims),
                     CartesianIndex(offset))

CroppingOperator(::Tuple{Vararg{Int}}, ::Tuple{Vararg{Int}}) =
    error("numbers of output and input dimensions must be equal")

CroppingOperator(::Tuple{Vararg{Int}}, ::Tuple{Vararg{Int}}, ::CartesianIndex) =
    error("numbers of output and input dimensions and offsets must be equal")

CroppingOperator(outdims::NTuple{N,Int}, inpdims::NTuple{N,Int}) where {N} =
    CroppingOperator{N}(outdims, inpdims)

CroppingOperator(outdims::NTuple{N,Int}, inpdims::NTuple{N,Int},
                 offset::CartesianIndex{N}) where {N} =
    CroppingOperator{N}(outdims, inpdims, offset)

function vcreate(::Type{Direct},
                 C::CroppingOperator{N},
                 x::AbstractArray{T,N},
                 scratch::Bool) where {T,N}
    (scratch && isa(x, Array{T,N}) && input_size(C) == output_size(C)) ? x :
        Array{T,N}(undef, output_size(C))
end

function vcreate(::Type{Adjoint},
                 C::CroppingOperator{N},
                 x::AbstractArray{T,N},
                 scratch::Bool) where {T,N}
    (scratch && isa(x, Array{T,N}) && input_size(C) == output_size(C)) ? x :
        Array{T,N}(undef, input_size(C))
end

# Apply cropping operation.
#
#     for I in R
#         J = I + K
#         y[I] = α*x[J] + β*y[I]
#     end
#
function apply!(α::Number,
                ::Type{Direct},
                C::CroppingOperator{N},
                x::AbstractArray{T,N},
                scratch::Bool,
                β::Number,
                y::AbstractArray{T,N}) where {T,N}
    has_standard_indexing(x) ||
        bad_argument("input array has non-standard indexing")
    size(x) == input_size(C) ||
        bad_size("bad input array dimensions")
    has_standard_indexing(y) ||
        bad_argument("output array has non-standard indexing")
    size(y) == output_size(C) ||
        bad_size("bad output array dimensions")
    if α == 0
        β == 1 || vscale!(y, β)
    else
        k = offset(C)
        I = commonpart(C)
        if α == 1
            if β == 0
                @inbounds @simd for i in I
                    y[i] = x[i + k]
                end
            elseif β == 1
                @inbounds @simd for i in I
                    y[i] += x[i + k]
                end
            else
                beta = convert(T, β)
                @inbounds @simd for i in I
                    y[i] = x[i + k] + beta*y[i]
                end
            end
        else
            alpha = convert(T, α)
            if β == 0
                @inbounds @simd for i in I
                    y[i] = alpha*x[i + k]
                end
            elseif β == 1
                @inbounds @simd for i in I
                    y[i] += alpha*x[i + k]
                end
            else
                beta = convert(T, β)
                @inbounds @simd for i in I
                    y[i] = alpha*x[i + k] + beta*y[i]
                end
            end
        end
    end
    return y
end

# Apply zero-padding operation.
#
#     for i in I
#         y[i + k] = α*x[i] + β*y[i + k]
#     end
#     # Plus y[i + k] *= β outside common region R
#
function apply!(α::Number,
                ::Type{Adjoint},
                C::CroppingOperator{N},
                x::AbstractArray{T,N},
                scratch::Bool,
                β::Number,
                y::AbstractArray{T,N}) where {T,N}
    has_standard_indexing(x) ||
        bad_argument("input array has non-standard indexing")
    size(x) == output_size(C) ||
        bad_size("bad input array dimensions")
    has_standard_indexing(y) ||
        bad_argument("output array has non-standard indexing")
    size(y) == input_size(C) ||
        bad_size("bad output array dimensions")
    β == 1 || vscale!(y, β)
    if α != 0
        k = offset(C)
        I = commonpart(C)
        if α == 1
            if β == 0
                @inbounds @simd for i in I
                    y[i + k] = x[i]
                end
            else
                @inbounds @simd for i in I
                    y[i + k] += x[i]
                end
            end
        else
            alpha = convert(T, α)
            if β == 0
                @inbounds @simd for i in I
                    y[i + k] = alpha*x[i]
                end
            else
                @inbounds @simd for i in I
                    y[i + k] += alpha*x[i]
                end
            end
        end
    end
    return y
end

"""
    ZeroPaddingOperator(outdims, inpdims, offset=defaultoffset(outdims,inpdims))

yields a linear map which implements zero-padding of arrays of size `inpdims`
to produce arrays of size `outdims`.  By default, the input array is centered
with respect to the output array (using the same conventions as `fftshift`).
Optional argument `offset` can be used to specify a different relative
position.  If `offset` is given, the input value at multi-dimensional index `j`
is copied at index `i = j + offset` in the result.

A zero-padding operator is implemented as the adjoint of a cropping operator.

See also: [`CroppingOperator`](@ref).

"""
ZeroPaddingOperator(outdims, inpdims) =
    Adjoint(CroppingOperator(inpdims, outdims))
ZeroPaddingOperator(outdims, inpdims, offset) =
    Adjoint(CroppingOperator(inpdims, outdims, offset))

"""
    defaultoffset(dim1,dim2)

yields the index offset such that the centers (in the same sense as assumed by
`fftshift`) of dimensions of lengths `dim1` and `dim2` are coincident.  If `off
= defaultoffset(dim1,dim2)` and `i2` is the index along `dim2`, then the index
along `dim1` is `i1 = i2 + off`.

"""
defaultoffset(dim1::Integer, dim2::Integer) =
    (Int(dim1) >> 1) - (Int(dim2) >> 1)
defaultoffset(dims1::NTuple{N,Integer}, dims2::NTuple{N,Integer}) where {N} =
    CartesianIndex(map(defaultoffset, dims1, dims2))

end # module
