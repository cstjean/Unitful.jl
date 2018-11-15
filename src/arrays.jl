using StaticArrays

export UnitfulArray, UnitfulVector, UnitfulMatrix

const TupleOf{T} = NTuple{N, T} where N

# Perhaps we should have U<:NTuple{N}. That way, one could use vectors of units,
# which _sounds_ bad (type-unstable), but it's just O(N) bad, compared to the
# O(N^2) or O(N^3) linear algebra operations. It would still be a win over a plain
# Matrix{Any} that stores unitful quantities.
struct UnitfulArray{T, N, A<:AbstractArray{T, N}, U<:NTuple{N, TupleOf{Units}}} <: AbstractArray{Quantity{T}, N}
    arr::A
    units::U
end
UnitfulArray(arr::AbstractArray{<:Any, N}, units::Vararg{TupleOf{Units}, N}) where N =
    UnitfulArray(arr, units)
Base.convert(::Type{UnitfulArray}, arr::AbstractArray{<:Real, N}) where N =
    UnitfulArray(arr, ntuple(i->ntuple(_->NoUnits, size(arr, i)), N))
const UnitfulVector{T} = UnitfulArray{T, 1}
const UnitfulMatrix{T} = UnitfulArray{T, 2}
const UnitfulVecOrMat{T} = Union{UnitfulVector{T}, UnitfulMatrix{T}}
UnitfulVector(arr, u1) = UnitfulArray(arr, u1)
UnitfulMatrix(arr, u1, u2) = UnitfulArray(arr, u1, u2)

row_units(ua::UnitfulArray) = ua.units[1]
column_units(ua::UnitfulArray) = ua.units[2]

Base.size(ua::UnitfulArray) = size(ua.arr)
Base.getindex(ua::UnitfulArray{T, N}, inds::Vararg{Int, N}) where {T, N} =
    ua.arr[inds...] * prod(getindex.(ua.units, inds))

# Alternative StaticArrays-free implementation
# function uconvert_rows(desired_row_units::TupleOf{Units}, uarr::UnitfulArray)
#     # This if looks nice, but we'd have to make sure that it doesn't introduce
#     # type instability
#     # if all(desired_row_units.==row_units(uarr))
#     #     # avoid the conversion factor if possible
#     #     return uarr
#     # end
    
#     # broadcasting is equivalent to left-multiplication by a diagonal matrix
#     # (which would be cleaner, but it involves allocating a vector, or
#     # using a StaticArrays.SVector)
#     # Float64 is because I get a segfault on my machine otherwise :( TODO: take out
#     factors = Float64.((convfact.(desired_row_units, row_units(uarr))...,))
#     return UnitfulArray(factors .* uarr.arr, desired_row_units, Base.tail(uarr.units)...)
# end

""" A diagonal matrix with the from_units -> to_units conversion factors on the 
diagonal. """
convmat(to_units, from_units) = Diagonal(Float64.(SVector(convfact.(to_units, from_units)...)))

""" Scale the rows of `ua` so that it has units `row_units`, or throw a DimensionError.
"""
uconvert_rows(row_units::TupleOf{Units}, uvec::UnitfulVector) =
    UnitfulArray(convmat(row_units, uvec.units[1]) * uvec.arr, row_units)
uconvert_rows(row_units::TupleOf{Units}, umat::UnitfulMatrix) =
    UnitfulArray(convmat(row_units, umat.units[1]) * umat.arr, row_units, umat.units[2])
uconvert_columns(col_units::TupleOf{Units}, umat::UnitfulMatrix) =
    UnitfulArray(umat.arr * convmat(col_units, umat.units[2]), umat.units[1], col_units)

for i in 1:2
    # Deal with method ambiguities by defining lots of methods
    @eval *(a::UnitfulMatrix, b::UnitfulArray{<:Any, $i}) =
        UnitfulArray(a.arr * uconvert_rows(column_units(a).^-1, b).arr,
                     row_units(a), Base.tail(b.units)...)
    for j in 1:2
        @eval *(a::UnitfulArray{<:Any, $i}, b::AbstractArray{<:Any, $j}) =
            a * convert(UnitfulArray, b)
        @eval *(a::AbstractArray{<:Any, $j}, b::UnitfulArray{<:Any, $i}) =
            convert(UnitfulArray, a) * b
    end
end
Base.inv(umat::UnitfulMatrix) =
    UnitfulMatrix(inv(umat.arr), umat.units[2].^-1, umat.units[1].^-1)
Base.adjoint(umat::UnitfulMatrix) =
    UnitfulMatrix(adjoint(umat.arr), umat.units[2], umat.units[1])
Base.adjoint(uvec::UnitfulVector) =
    UnitfulMatrix(adjoint(uvec.arr), (NoUnits,), uvec.units[1])

struct UnitfulCholesky{T, U} #{T,S<:AbstractMatrix} <: Factorization{T}
    unitless_chol::T
    input_units::U
end
cholesky(uarr::UnitfulArray) = UnitfulCholesky(cholesky(uarr.arr), uarr.units)
function getproperty(UC::UnitfulCholesky, d::Symbol)
    res = getproperty(getfield(UC, :unitless_chol), d)
    inp_units = getfield(UC, :input_units)
    if d == :U
        units = (map(_->NoUnits, inp_units[1]), inp_units[2])
    elseif d == :L
        units = (inp_units[1], map(_->NoUnits, inp_units[2]))
    elseif d == :UL
        TODO()  # UL is not documented in the docstring
    else
        return getfield(UC, d)
    end
    return UnitfulArray(res, units)
end

""" Similar to promote, convert the units of `(a, b)` into `(new_a, new_b)` such that 
the units of `new_a` and `new_b` are the same. """
compatible_units(a::UnitfulVector, b::UnitfulVector) =
    (a, uconvert_rows(row_units(a), b))
compatible_units(a::UnitfulMatrix, b::UnitfulMatrix) =
    (a, uconvert_columns(column_units(a), uconvert_rows(row_units(a), b)))
function apply(op, a::UnitfulArray{N}, b::UnitfulArray{N}) where N
    a2, b2 = compatible_units(a, b)
    return UnitfulArray(op(a2.arr, b2.arr), a2.units)
end

+(a::UnitfulArray, b::UnitfulArray) = apply(+, a, b)
-(a::UnitfulArray, b::UnitfulArray) = apply(-, a, b)
    
ustrip(a::UnitfulArray) = a.arr
unit(a::UnitfulArray) = a.units   # an abuse of terminology (singular/plural). Delete?
