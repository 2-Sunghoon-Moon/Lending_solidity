
def test(p, rate, n):
    k = p / 1000
    _n = ((rate + 1) ** n) - 1
    _d = ((rate + 1) - 1)

    result = p + (k * (_n/_d))


    return result


print((test(2000, 0.01, 1500) - 2000) * (3/13))
    