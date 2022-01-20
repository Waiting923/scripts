'''
给定一个只包括 '('，')'，'{'，'}'，'['，']' 的字符串 s ，判断字符串是否有效。

有效字符串需满足:

左括号必须用相同类型的右括号闭合。
左括号必须以正确的顺序闭合。


示例 1:

输入:s = "()"
输出:true
示例 2:

输入:s = "()[]{}"
输出:true
示例 3:

输入:s = "(]"
输出:false
示例 4:

输入:s = "([)]"
输出:false
示例 5:

输入:s = "{[]}"
输出:true
'''

import pdb

class Solution:
    def isValid(self, s: str) -> bool:
        l = list(s)
        a = ['(', '{', '[']
        b = [')', '}', ']']
        for i in range(len(l)):
            if l[i] not in a and l[i] not in b:
                return False
        for x in range(len(a)):
            if (a[x] in l and b[x] in l) and (l.index(a[x]) < l.index(b[x])):
                if (l.index(b[x]) - l.index(a[x])) % 2 == 0:
                    return False
            elif a[x] not in l and b[x] not in l:
                continue
            else:
                return False

    def main(self):
        print(bool(self.isValid(s)== None))

'''
class Solution:
    def isValid(self, s):
        while '{}' in s or '()' in s or '[]' in s:
            s = s.replace('{}', '')
            s = s.replace('()', '')
            s = s.replace('[]', '')
        return s == ''

    def main(self):
        print(self.isValid(s))
'''    
if __name__ == '__main__':
    #pdb.set_trace()
    s = "([]){"
    S = Solution()
    S.main()