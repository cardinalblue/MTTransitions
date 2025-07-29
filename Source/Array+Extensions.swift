//
//  Array+Extensions.swift
//  MTTransitions
//
//  Created by Jim Wang on 2022/6/4.
//

import Foundation

extension Array {

    /**
     * Return a pairwise array
     * Input  : [0, 1, 2, 3, 4]
     * Output : [[0, 1], [1, 2], [2, 3], [3, 4]]
     */
    func pairwise() -> [(Element, Element)] {
        var result = [(Element, Element)]()
        if count < 2 {
            return result
        }

        for index in 0..<count - 1 {
            result.append((self[index], self[index + 1]))
        }
        return result
    }

}
