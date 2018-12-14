#
# utils.jl -
#
# General purpose methods.
#
#-------------------------------------------------------------------------------
#
# This file is part of LazyAlgebra (https://github.com/emmt/LazyAlgebra.jl)
# released under the MIT "Expat" license.
#
# Copyright (c) 2017-2018 Éric Thiébaut.
#

"""
```julia
is_flat_array(A) -> boolean
```

yields whether array `A` can be indexed as a *flat* array, that is an array
with contiguous elements and first element at index 1.  This also means that
`A` has 1-based indices along all its dimensions.

Several arguments can be checked in a single call:

```julia
is_flat_array(A, B, C, ...)
```

is the same as:

```julia
is_flat_array(A) && is_flat_array(B) && is_flat_array(C) && ...
```

"""
is_flat_array(A::DenseArray) = true

function is_flat_array(A::AbstractArray{T,N}) where {T,N}
    Base.has_offset_axes(A) && return false
    n = 1
    @inbounds for d in 1:N
        stride(A, d) == n || return false
        n *= size(A, d)
    end
    return true
end

is_flat_array() = false
is_flat_array(::Any) = false
is_flat_array(args...) = allof(is_flat_array, args...)
#
# Above version could be:
#
#     is_flat_array(args...) = all(is_flat_array, args)
#
# but using `all(is_flat_array, A, x, y)` for `A`, `x` and `y` flat arrays of
# sizes (3,4,5,6), (5,6) and (3,4) takes 9.0ns (with Julia 1.0, 29.1ns with
# Julia 0.6) while using `allof` takes 0.02ns (i.e. is eliminated by the
# compiler).
#

"""
```julia
allof(p, args...) -> Bool
```

checks whether predicate `p` returns `true` for all arguments `args...`,
returning `false` as soon as possible (short-circuiting).

```julia
allof(args...) -> Bool
```

checks whether all arguments `args...` are `true`, returning `false` as soon as
possible (short-circuiting).  Arguments can be booleans or arrays of booleans.
The latter are considered as `true` if all their elements are `true` and are
considered as `false` otherwise (if any of their elements are `false`).
Arguments can also be iterables to check whether all their values are `true`.
As a consequence, an empty iterable is considered as `true`.

This method can be much faster than `all(p, args)` or `all(args)` because its
result may be determined at compile time.  However, `missing` values are not
considered as special.

See also: [`all`](@ref), [`anyof`](@ref), [`noneof`](@ref).

"""
allof(p::Function, a) = p(a)::Bool
allof(p::Function, a, b...) = p(a) && allof(p, b...)
allof(a, b...) = allof(a) && allof(b...)
allof(a::Bool) = a
function allof(a::AbstractArray{Bool})
    @inbounds for i in eachindex(a)
        a[i] || return false
    end
    return true
end
function allof(itr)
    for val in itr
        allof(val) || return false
    end
    return true
end

"""
```julia
anyof(p, args...) -> Bool
```

checks whether predicate `p` returns `true` for any argument `args...`,
returning `true` as soon as possible (short-circuiting).

```julia
anyof(args...) -> Bool
```

checks whether all arguments `args...` are `true`, returning `false` as soon as
possible (short-circuiting).  Arguments can be booleans or arrays of booleans.
The latter are considered as `true` if any of their elements are `true` and are
considered as `false` otherwise (if all their elements are `false`).  Arguments
can also be iterables to check whether any of their values are `true`.  As a
consequence, an empty iterable is considered as `false`.

This method can be much faster than `any(p, args)` or `any(args)` because its
result may be determined at compile time.  However, `missing` values are not
considered as special.

To check whether predicate `p` returns `false` for all argument `args...`
or whether all argument `args...` are false, repectively call:

```julia
noneof(p, args...) -> Bool
```

or

```julia
noneof(args...) -> Bool
```

which are the same as `!anyof(p, args...)` and `!anyof(args...)`.

See also: [`any`](@ref), [`allof`](@ref).

"""
anyof(p::Function, a) = p(a)::Bool
anyof(p::Function, a, b...) = p(a) || anyof(p, b...)
anyof(a, b...) = anyof(a) || anyof(b...)
anyof(a::Bool) = a
function anyof(a::AbstractArray{Bool})
    @inbounds for i in eachindex(a)
        a[i] && return true
    end
    return false
end
function anyof(itr)
    for val in itr
        anyof(val) && return true
    end
    return false
end

noneof(args...) = ! anyof(args...)
@doc @doc(anyof) noneof
