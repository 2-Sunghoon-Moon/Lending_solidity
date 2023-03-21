
def test(p, rate, n):
    k = p / 1000
    _n = ((rate + 1) ** n) - 1
    _d = ((rate + 1) - 1)

    result = p + (k * (_n/_d))


    return result


print(test(1000, 0.01, 3))
    