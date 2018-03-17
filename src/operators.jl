#
# operators.jl -
#
# Methods for linear operators.
#
#-------------------------------------------------------------------------------
#
# This file is part of the LazyAlgebra package released under the MIT "Expat"
# license.
#
# Copyright (c) 2017-2018 Éric Thiébaut.
#

# Note that we extend the meaning of * and \ only for linear operators (not for
# arrays using the generalized matrix-vector dot product).
(*)(A::LinearOperator, x) = apply(Direct, A, x)
(\)(A::LinearOperator, x) = apply(Inverse, A, x)

Inverse(A::Inverse) = A.op
Inverse(A::Adjoint{T}) where {T<:LinearOperator} = InverseAdjoint{T}(A.op)
Inverse(A::InverseAdjoint{T}) where {T<:LinearOperator} = Adjoint{T}(A.op)

Adjoint(A::Adjoint) = A.op
Adjoint(A::Inverse{T}) where {T<:LinearOperator} = InverseAdjoint{T}(A.op)
Adjoint(A::InverseAdjoint{T}) where {T<:LinearOperator} = Inverse{T}(A.op)

InverseAdjoint(A::InverseAdjoint) = A.op
InverseAdjoint(A::Adjoint{T}) where {T<:LinearOperator} = Inverse{T}(A.op)
InverseAdjoint(A::Inverse{T}) where {T<:LinearOperator} = Adjoint{T}(A.op)

# Manage to have A' and inv(A) adds the correct decoration:
Base.ctranspose(A::LinearOperator) = Adjoint(A)
Base.inv(A::LinearOperator) = Inverse(A)

# Automatically unveils operator for common methods.
for (T1, T2, T3) in ((:Direct,         :Adjoint,        :Adjoint),
                     (:Direct,         :Inverse,        :Inverse),
                     (:Direct,         :InverseAdjoint, :InverseAdjoint),
                     (:Adjoint,        :Adjoint,        :Direct),
                     (:Adjoint,        :Inverse,        :InverseAdjoint),
                     (:Adjoint,        :InverseAdjoint, :Inverse),
                     (:Inverse,        :Adjoint,        :InverseAdjoint),
                     (:Inverse,        :Inverse,        :Direct),
                     (:Inverse,        :InverseAdjoint, :Adjoint),
                     (:InverseAdjoint, :Adjoint,        :Inverse),
                     (:InverseAdjoint, :Inverse,        :Adjoint),
                     (:InverseAdjoint, :InverseAdjoint, :Direct))
    @eval begin

        apply!(y, ::Type{$T1}, A::$T2, x) =
            apply!(y, $T3, A.op, x)

        apply(::Type{$T1}, A::$T2, x) =
            apply($T3, A.op, x)

        vcreate(::Type{$T1}, A::$T2, x) =
            vcreate($T3, A.op, x)

        is_applicable_in_place(::Type{$T1}, A::$T2, x) =
            is_applicable_in_place($T3, A.op, x)
    end

end

# Specialize methods for self-adjoint operators so that only `Direct` and
# `Inverse` operations need to be implemented.
Adjoint(A::SelfAdjointOperator) = A
InverseAdjoint(A::SelfAdjointOperator) = Inverse(A)
for (T1, T2) in ((:Adjoint, :Direct),
                 (:InverseAdjoint, :Inverse))
    @eval begin

        apply!(y, ::Type{$T1}, A::SelfAdjointOperator, x) =
            apply!(y, $T2, A, x)

        apply(::Type{$T1}, A::SelfAdjointOperator, x) =
            apply($T2, A, x)

        vcreate(::Type{$T1}, A::SelfAdjointOperator, x) =
            vcreate($T2, A, x)

        is_applicable_in_place(::Type{$T1}, A::SelfAdjointOperator, x) =
            is_applicable_in_place($T2, A, x)

    end
end

# Basic methods:
"""
```julia
input_type([P=Direct,] A)
output_type([P=Direct,] A)
```

yield the (preferred) types of the input and output arguments of the operation
`P` with operator `A`.  If `A` operates on Julia arrays, the element type,
list of dimensions, `i`-th dimension and number of dimensions for the input and
output are given by:

    input_eltype([P=Direct,] A)          output_eltype([P=Direct,] A)
    input_size([P=Direct,] A)            output_size([P=Direct,] A)
    input_size([P=Direct,] A, i)         output_size([P=Direct,] A, i)
    input_ndims([P=Direct,] A)           output_ndims([P=Direct,] A)

Only `input_size(A)` and `output_size(A)` have to be implemented.

Also see: [`vcreate`](@ref), [`apply!`](@ref), [`LinearOperator`](@ref),
[`Operations`](@ref).

"""
function input_type end

for sfx in (:size, :eltype, :ndims, :type),
    pfx in (:output, :input)

    fn1 = Symbol(pfx, "_", sfx)

    for P in (Direct, Adjoint, Inverse, InverseAdjoint)

         fn2 = Symbol(P == Adjoint || P == Inverse ?
                     (pfx == :output ? :input : :output) : pfx, "_", sfx)

        #println("$fn1($P) -> $fn2")

        # Provide basic methods for the different operations and for tagged
        # operators.
        @eval begin

            if $(P != Direct)
                $fn1(A::$P{<:LinearOperator}) = $fn2(A.op)
            end

            $fn1(::Type{$P}, A::LinearOperator) = $fn2(A)

            if $(sfx == :size)
                if $(P != Direct)
                    $fn1(A::$P{<:LinearOperator}, dim...) =
                        $fn2(A.op, dim...)
                end
                $fn1(::Type{$P}, A::LinearOperator, dim...) =
                    $fn2(A, dim...)
            end
        end
    end

    # Link documentation for the basic methods.
    @eval begin
        if $(fn1 != :input_type)
            @doc @doc(:input_type) $fn1
        end
    end

end

# Provide default methods for `$(sfx)_size(A, dim...)` and `$(sfx)_ndims(A)`.
for pfx in (:input, :output)
    pfx_size = Symbol(pfx, "_size")
    pfx_ndims = Symbol(pfx, "_ndims")
    @eval begin

        $pfx_ndims(A::LinearOperator) = length($pfx_size(A))

        $pfx_size(A::LinearOperator, dim) = $pfx_size(A)[dim]

        function $pfx_size(A::LinearOperator, dim...)
            dims = $pfx_size(A)
            ntuple(i -> dims[dim[i]], length(dim))
        end

    end
end


"""
```julia
is_applicable_in_place([P,] A, x)
```

yields whether operator `A` is applicable *in-place* for performing operation
`P` with argument `x`, that is with the result stored into the argument `x`.
This can be used to spare allocating ressources.

See also: [`LinearOperator`](@ref), [`apply!`](@ref).

"""
is_applicable_in_place(::Type{<:Operations}, A::LinearOperator, x) = false
is_applicable_in_place(A::LinearOperator, x) =
    is_applicable_in_place(Direct, A, x)

#------------------------------------------------------------------------------
# IDENTITY

"""
```julia
Identity()
```

yields the identity linear operator.  Beware that the purpose of this operator
is to be as efficient as possible, hence the result of applying this operator
may be the same as the input argument.

"""
struct Identity <: SelfAdjointOperator; end

is_applicable_in_place(::Type{<:Operations}, ::Identity, x) = true

Base.inv(A::Identity) = A

apply(::Type{<:Operations}, ::Identity, x) = x

apply!(α::Scalar, ::Type{<:Operations}, ::Identity, x, β::Scalar, y) =
    vcombine!(y, α, x, β, y)

vcreate(::Type{<:Operations}, ::Identity, x) = similar(x)

#------------------------------------------------------------------------------
# UNIFORM SCALING

"""
```julia
UniformScalingOperator(α)
```

creates a uniform scaling linear operator whose effects is to multiply its
argument by the scalar `α`.

See also: [`NonuniformScalingOperator`](@ref).

"""
struct UniformScalingOperator <: SelfAdjointOperator
    α::Float64
end

is_applicable_in_place(::Type{<:Operations}, ::UniformScalingOperator, x) = true

isinvertible(A::UniformScalingOperator) = (isfinite(A.α) && A.α != 0.0)

ensureinvertible(A::UniformScalingOperator) =
    isinvertible(A) || throw(
        SingularSystem("Uniform scaling operator is singular"))

function Base.inv(A::UniformScalingOperator)
    ensureinvertible(A)
    return UniformScalingOperator(1.0/A.α)
end

function apply!(α::Scalar, ::Type{<:Union{Direct,Adjoint}},
                A::UniformScalingOperator, x, β::Scalar, y)
    return vcombine!(y, α*A.α, x, β, y)
end

function apply!(α::Scalar, ::Type{<:Union{Inverse,InverseAdjoint}},
                A::UniformScalingOperator, x, β::Scalar, y)
    ensureinvertible(A)
    return vcombine!(y, α/A.α, x, β, y)
end

function vcreate(::Type{<:Operations},
                 A::UniformScalingOperator,
                 x::AbstractArray{T,N}) where {T<:Real,N}
    return similar(Array{float(T)}, indices(x))
end

vcreate(::Type{<:Operations}, A::UniformScalingOperator, x) =
    vcreate(x)

#------------------------------------------------------------------------------
# NON-UNIFORM SCALING

"""
```julia
NonuniformScalingOperator(A)
```

creates a nonuniform scaling linear operator whose effects is to apply
elementwise multiplication of its argument by the scaling factors `A`.
This operator can be thought as a *diagonal* operator.

See also: [`UniformScalingOperator`](@ref).

"""
struct NonuniformScalingOperator{T} <: SelfAdjointOperator
    scl::T
end

is_applicable_in_place(::Type{<:Operations}, ::NonuniformScalingOperator, x) =
    true

function Base.inv(A::NonuniformScalingOperator{<:AbstractArray{T,N}}
                  ) where {T<:AbstractFloat, N}
    q = A.scl
    r = similar(q)
    @inbounds @simd for i in eachindex(q, r)
        r[i] = one(T)/q[i]
    end
    return NonuniformScalingOperator(r)
end

function apply!(α::Scalar,
                ::Type{<:Union{Direct,Adjoint}},
                A::NonuniformScalingOperator{<:AbstractArray{<:AbstractFloat,N}},
                x::AbstractArray{<:AbstractFloat,N},
                β::Scalar,
                y::AbstractArray{<:AbstractFloat,N}) where {N}
    w = A.scl
    @assert indices(w) == indices(x) == indices(y)
    T = promote_type(eltype(w), eltype(x), eltype(y))
    if α == one(α)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = w[i]*x[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = w[i]*x[i] + y[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = w[i]*x[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = w[i]*x[i] + beta*y[i]
            end
        end
    elseif α == zero(α)
        vscale!(y, β)
    elseif α == -one(α)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = -w[i]*x[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = y[i] - w[i]*x[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = -w[i]*x[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = beta*y[i] - w[i]*x[i]
            end
        end
    else
        alpha = convert(T, β)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*w[i]*x[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*w[i]*x[i] + y[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*w[i]*x[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*w[i]*x[i] + beta*y[i]
            end
        end
    end
    return y
end

function apply!(α::Scalar,
                ::Type{<:Union{Inverse,InverseAdjoint}},
                A::NonuniformScalingOperator{<:AbstractArray{<:AbstractFloat,N}},
                x::AbstractArray{<:AbstractFloat,N},
                β::Scalar,
                y::AbstractArray{<:AbstractFloat,N}) where {N}
    w = A.scl
    @assert indices(w) == indices(x) == indices(y)
    T = promote_type(eltype(w), eltype(x), eltype(y))
    if α == one(α)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = x[i]/w[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = x[i]/w[i] + y[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = x[i]/w[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = x[i]/w[i] + beta*y[i]
            end
        end
    elseif α == zero(α)
        vscale!(y, β)
    elseif α == -one(α)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = -x[i]/w[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = y[i] - x[i]/w[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = -x[i]/w[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = beta*y[i] - x[i]/w[i]
            end
        end
    else
        alpha = convert(T, β)
        if β == zero(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*x[i]/w[i]
            end
        elseif β == one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*x[i]/w[i] + y[i]
            end
        elseif β == -one(β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*x[i]/w[i] - y[i]
            end
        else
            beta = convert(T, β)
            @inbounds @simd for i in eachindex(w, x, y)
                y[i] = alpha*x[i]/w[i] + beta*y[i]
            end
        end
    end
    return y
end

function vcreate(::Type{<:Operations},
                 A::NonuniformScalingOperator{<:AbstractArray{Ta,N}},
                 x::AbstractArray{Tx,N}) where {Ta<:AbstractFloat,
                                                Tx<:AbstractFloat, N}
    inds = indices(A.scl)
    @assert indices(x) == inds
    T = promote_type(Ta, Tx)
    return similar(Array{T}, inds)
end

#------------------------------------------------------------------------------
# RANK-1 OPERATORS

"""

A `RankOneOperator` is defined by two *vectors* `u` and `v` and created by:

```julia
A = RankOneOperator(u, v)
```

and behaves as if `A = u⋅v'`; that is:

```julia
A*x  = vscale(vdot(v, x)), u)
A'*x = vscale(vdot(u, x)), v)
```

See also: [`SymmetricRankOneOperator`](@ref), [`LinearOperator`](@ref),
          [`apply!`](@ref), [`vcreate`](@ref).

"""
struct RankOneOperator{U,V} <: LinearOperator
    u::U
    v::V
end

function apply!(α::Scalar, ::Type{Direct}, A::RankOneOperator, x,
                β::Scalar, y)
    if α == zero(α)
        # Lazily assume that y has correct type, dimensions, etc.
        vscale!(y, β)
    else
        vcombine!(y, α*vdot(A.v, x), A.u, β, y)
    end
    return y
end

function apply!(α::Scalar, ::Type{Adjoint}, A::RankOneOperator, x,
                β::Scalar, y)
    if α == zero(α)
        # Lazily assume that y has correct type, dimensions, etc.
        vscale!(y, β)
    else
        vcombine!(y, α*vdot(A.u, x), A.v, β, y)
    end
    return y
end

# Lazily assume that x has correct type, dimensions, etc.
vcreate(::Type{Direct}, A::RankOneOperator, x) = vcreate(A.v)
vcreate(::Type{Adjoint}, A::RankOneOperator, x) = vcreate(A.u)

input_type(A::RankOneOperator{U,V}) where {U,V} = V
input_ndims(A::RankOneOperator) = ndims(A.v)
input_size(A::RankOneOperator) = size(A.v)
input_size(A::RankOneOperator, d...) = size(A.v, d...)
input_eltype(A::RankOneOperator) = eltype(A.v)

output_type(A::RankOneOperator{U,V}) where {U,V} = U
output_ndims(A::RankOneOperator) = ndims(A.u)
output_size(A::RankOneOperator) = size(A.u)
output_size(A::RankOneOperator, d...) = size(A.u, d...)
output_eltype(A::RankOneOperator) = eltype(A.u)

"""

A `SymmetricRankOneOperator` is defined by a *vector* `u` and created by:

```julia
A = SymmetricRankOneOperator(u)
```

and behaves as if `A = u⋅u'`; that is:

```julia
A*x = A'*x = vscale(vdot(u, x)), u)
```

See also: [`RankOneOperator`](@ref), [`LinearOperator`](@ref),
          [`SelfAdjointOperator`](@ref) [`apply!`](@ref), [`vcreate`](@ref).

"""
struct SymmetricRankOneOperator{U} <: SelfAdjointOperator
    u::U
end

is_applicable_in_place(::Type{<:Operations}, ::SymmetricRankOneOperator) = true

function apply!(α::Scalar, ::Type{P}, A::SymmetricRankOneOperator, x,
                β::Scalar, y) where {P<:Union{Direct,Adjoint}}
    if α == zero(α)
        # Lazily assume that y has correct type, dimensions, etc.
        vscale!(y, β)
    else
        vcombine!(y, α*vdot(A.u, x), A.u, β, y)
    end
    return y
end

function vcreate(::Type{P}, A::SymmetricRankOneOperator,
                 x) where {P<:Union{Direct,Adjoint}}
    # Lazily assume that x has correct type, dimensions, etc.
    vcreate(A.u)
end

input_type(A::SymmetricRankOneOperator{U}) where {U} = U
input_ndims(A::SymmetricRankOneOperator) = ndims(A.u)
input_size(A::SymmetricRankOneOperator) = size(A.u)
input_size(A::SymmetricRankOneOperator, d...) = size(A.u, d...)
input_eltype(A::SymmetricRankOneOperator) = eltype(A.u)

# FIXME: this should be automatically done for SelfAdjointOperators?
output_type(A::SymmetricRankOneOperator{U}) where {U} = U
output_ndims(A::SymmetricRankOneOperator) = ndims(A.u)
output_size(A::SymmetricRankOneOperator) = size(A.u)
output_size(A::SymmetricRankOneOperator, d...) = size(A.u, d...)
output_eltype(A::SymmetricRankOneOperator) = eltype(A.u)

#------------------------------------------------------------------------------
# GENERALIZED MATRIX AND MATRIX-VECTOR PRODUCT

"""
```julia
GeneralMatrix(A)
```

creates a linear operator given a multi-dimensional array `A` whose interest is
to generalize the definition of the matrix-vector product without calling
`reshape` to change the dimensions.

For instance, assuming that `G = GeneralMatrix(A)` with `A` a regular array,
then `y = G*x` requires that the dimensions of `x` match the trailing
dimensions of `A` and yields a result `y` whose dimensions are the remaining
leading dimensions of `A`, such that `indices(A) = (indices(y)...,
indices(x)...)`.  Applying the adjoint of `G` as in `y = G'*x` requires that
the dimensions of `x` match the leading dimension of `A` and yields a result
`y` whose dimensions are the remaining trailing dimensions of `A`, such that
`indices(A) = (indices(x)..., indices(y)...)`.

See also: [`reshape`](@ref).

"""
struct GeneralMatrix{T<:AbstractArray} <: LinearOperator
    arr::T
end

# Make a GeneralMatrix behaves like an ordinary array.
Base.eltype(A::GeneralMatrix) = eltype(A.arr)
Base.length(A::GeneralMatrix) = length(A.arr)
Base.ndims(A::GeneralMatrix) = ndims(A.arr)
Base.indices(A::GeneralMatrix) = indices(A.arr)
Base.size(A::GeneralMatrix) = size(A.arr)
Base.size(A::GeneralMatrix, inds...) = size(A.arr, inds...)
Base.getindex(A::GeneralMatrix, inds...) = getindex(A.arr, inds...)
Base.setindex!(A::GeneralMatrix, x, inds...) = setindex!(A.arr, x, inds...)
Base.stride(A::GeneralMatrix, k) = stride(A.arr, k)
Base.strides(A::GeneralMatrix) = strides(A.arr)
Base.eachindex(A::GeneralMatrix) = eachindex(A.arr)

function apply!(α::Scalar,
                ::Type{P},
                A::GeneralMatrix{<:AbstractArray{<:AbstractFloat}},
                x::AbstractArray{<:AbstractFloat},
                β::Scalar,
                y::AbstractArray{<:AbstractFloat}) where {P<:Operations}
    return apply!(α, P, A.arr, x, β, y)
end

function vcreate(::Type{P},
                 A::GeneralMatrix{<:AbstractArray{<:AbstractFloat}},
                 x::AbstractArray{<:AbstractFloat}) where {P<:Operations}
    return vcreate(P, A.arr, x)
end

function apply(A::AbstractArray{<:Real},
               x::AbstractArray{<:Real})
    return apply(Direct, A, x)
end

function apply(::Type{P},
               A::AbstractArray{<:Real},
               x::AbstractArray{<:Real}) where {P<:Operations}
    return apply!(one(Scalar), P, A, x, zero(Scalar), vcreate(P, A, x))
end

# By default, use pure Julia code for the generalized matrix-vector product.
function apply!(α::Scalar,
                ::Type{P},
                A::AbstractArray{<:Real},
                x::AbstractArray{<:Real},
                β::Scalar,
                y::AbstractArray{<:Real}) where {P<:Union{Direct,
                                                          InverseAdjoint}}
    if indices(A) != (indices(y)..., indices(x)...)
        throw(DimensionMismatch("`x` and/or `y` have indices incompatible with `A`"))
    end
    return _apply!(α, P, A, x, β, y)
end

function apply!(α::Scalar,
                ::Type{P},
                A::AbstractArray{<:Real},
                x::AbstractArray{<:Real},
                β::Scalar,
                y::AbstractArray{<:Real}) where {P<:Union{Adjoint,Inverse}}
    if indices(A) != (indices(x)..., indices(y)...)
        throw(DimensionMismatch("`x` and/or `y` have indices incompatible with `A`"))
    end
    return _apply!(α, P, A, x, β, y)
end

function vcreate(::Type{P},
                 A::AbstractArray{Ta,Na},
                 x::AbstractArray{Tx,Nx}) where {Ta<:AbstractFloat, Na,
                                                 Tx<:AbstractFloat, Nx,
                                                 P<:Union{Direct,
                                                          InverseAdjoint}}
    inds = indices(A)
    Ny = Na - Nx
    if Nx ≥ Na || indices(x) != inds[Ny+1:end]
        throw(DimensionMismatch("the dimensions of `x` do not match the trailing dimensions of `A`"))
    end
    Ty = promote_type(Ta, Tx)
    return similar(Array{Ty}, inds[1:Ny])
end

function vcreate(::Type{P},
                 A::AbstractArray{Ta,Na},
                 x::AbstractArray{Tx,Nx}) where {Ta<:AbstractFloat, Na,
                                                 Tx<:AbstractFloat, Nx,
                                                 P<:Union{Adjoint,Inverse}}
    inds = indices(A)
    Ny = Na - Nx
    if Nx ≥ Na || indices(x) != inds[1:Nx]
        throw(DimensionMismatch("the dimensions of `x` do not match the leading dimensions of `A`"))
    end
    Ty = promote_type(Ta, Tx)
    return similar(Array{Ty}, inds[Ny+1:end])
end


# Pure Julia code implementations.

function _apply!(α::Scalar,
                 ::Type{Direct},
                 A::AbstractArray{Ta},
                 x::AbstractArray{Tx},
                 β::Scalar,
                 y::AbstractArray{Ty}) where {Ta<:Real, Tx<:Real, Ty<:Real}
    if β != one(β)
        vscale!(y, β)
    end
    if α != zero(α)
        # Loop through the coefficients of A assuming column-major storage
        # order.
        T = promote_type(Ta, Tx, Ty)
        alpha = convert(T, α)
        I, J = CartesianRange(indices(y)), CartesianRange(indices(x))
        @inbounds for j in J
            xj = alpha*convert(T, x[j])
            if xj != zero(xj)
                @simd for i in I
                    y[i] += A[i,j]*xj
                end
            end
        end
    end
    return y
end

function _apply!(y::AbstractArray{Ty},
                 ::Type{Adjoint},
                 A::AbstractArray{Ta},
                 x::AbstractArray{Tx}) where {Ta<:Real, Tx<:Real, Ty<:Real}
    return _apply!(promote_type(Ty, Ta, Tx), y, Adjoint, A, x)
end

function _apply!(α::Scalar,
                 ::Type{Adjoint},
                 A::AbstractArray{Ta},
                 x::AbstractArray{Tx},
                 β::Scalar,
                 y::AbstractArray{Ty}) where {Ta<:Real, Tx<:Real, Ty<:Real}
    if α == zero(α)
        vscale!(y, β)
    else
        # Loop through the coefficients of A assuming column-major storage
        # order.
        T = promote_type(Ta, Tx, Ty)
        alpha = convert(T, α)
        I, J = CartesianRange(indices(x)), CartesianRange(indices(y))
        if β == zero(β)
            @inbounds for j in J
                local s::T = zero(T)
                @simd for i in I
                    s += A[i,j]*x[i]
                end
                y[j] = alpha*s
            end
        else
            beta = convert(T, β)
            @inbounds for j in J
                local s::T = zero(T)
                @simd for i in I
                    s += A[i,j]*x[i]
                end
                y[j] = alpha*s + beta*y[j]
            end
        end
    end
    return y
end

#------------------------------------------------------------------------------
# HALF HESSIAN

"""

`HalfHessian(A)` is a container to be interpreted as the linear operator
representing the second derivatives (times 1/2) of some objective function at
some point both represented by `A` (which can be anything).  Given `H =
HalfHessian(A)`, the contents `A` is retrieved by `contents(H)`.

For a simple quadratic objective function like:

```
f(x) = ‖D⋅x‖²
```

the half-Hessian is:

```
H = D'⋅D
```

As the half-Hessian is symmetric, a single method `apply!` has to be
implemented to apply the direct and adjoint of the operator, the signature of
the method is:

```julia
apply!(y::T, ::Type{Direct}, H::HalfHessian{typeof(A)}, x::T)
```

where `y` is overwritten by the result of applying `H` (or its adjoint) to the
argument `x`.  Here `T` is the relevant type of the variables.  Similarly, to
allocate a new object to store the result of applying the operator, it is
sufficient to implement the method:

```julia
vcreate(::Type{Direct}, H::HalfHessian{typeof(A)}, x::T)
```

See also: [`LinearOperator`][@ref).

"""
struct HalfHessian{T} <: SelfAdjointOperator
    obj::T
end

"""
```julia
contents(C)
```

yields the contents of the container `C`.  A *container* is any type which
implements the `contents` method.

"""
contents(H::HalfHessian) = H.obj
