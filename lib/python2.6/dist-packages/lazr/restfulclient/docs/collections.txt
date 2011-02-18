***********
Collections
***********

lazr.restful makes collections of data available through Pythonic
mechanisms like slices.

    >>> from lazr.restfulclient.tests.example import CookbookWebServiceClient
    >>> service = CookbookWebServiceClient()

You can iterate through all the items in a collection.

    >>> names = sorted([recipe.dish.name for recipe in service.recipes])
    >>> len(names)
    5
    >>> names
    [u'Baked beans', ..., u'Roast chicken']

But it's almost always better to slice them.

    >>> sorted([recipe.dish.name for recipe in service.recipes[:2]])
    [u'Roast chicken', u'Roast chicken']

You can get a slice of any collection, so long as you provide start
and end points keyed to the beginning of the list. You can't key a
slice to the end of the list because it might be expensive to
calculate how big the list is.

This set-up code creates a regular Python list of all recipes on the
site, for comparison with a lazr.restful Collection object
representing the same list.

    >>> all_recipes = [recipe for recipe in service.recipes]
    >>> recipes = service.recipes

Calling len() on the Collection object makes sure that the first page
of representations is cached, which forces this test to test an
optimization.

    >>> ignored = len(recipes)

These tests demonstrate that slicing the collection resource gives the
same results as collecting all the entries in the collection, and
slicing an ordinary list.

    >>> def slices_match(slice):
    ...     """Slice two lists of recipes, then make sure they're the same."""
    ...     list1 = recipes[slice]
    ...     list2 = all_recipes[slice]
    ...     if len(list1) != len(list2):
    ...         raise ("Lists are different sizes: %d vs. %d" %
    ...                (len(list1), len(list2)))
    ...     for index in range(0, len(list1)):
    ...         if list1[index].id != list2[index].id:
    ...             raise ("%s doesn't match %s in position %d" %
    ...                    (list1[index].id, list2[index].id, index))
    ...     return True

    >>> slices_match(slice(3))
    True
    >>> slices_match(slice(50))
    True
    >>> slices_match(slice(1,2))
    True
    >>> slices_match(slice(2,21))
    True
    >>> slices_match(slice(2,21,3))
    True

    >>> slices_match(slice(0, 200))
    True
    >>> slices_match(slice(30, 200))
    True
    >>> slices_match(slice(60, 100))
    True

    >>> recipes[5:]
    Traceback (most recent call last):
    ...
    ValueError: Collection slices must have a definite, nonnegative end point.

    >>> recipes[10:-1]
    Traceback (most recent call last):
    ...
    ValueError: Collection slices must have a definite, nonnegative end point.

    >>> recipes[-1:]
    Traceback (most recent call last):
    ...
    ValueError: Collection slices must have a nonnegative start point.

    >>> recipes[:]
    Traceback (most recent call last):
    ...
    ValueError: Collection slices must have a definite, nonnegative end point.

You can slice a collection that's the return value of a named
operation.

    >>> e_recipes = service.cookbooks.find_recipes(search='e')
    >>> len(e_recipes[1:3])
    2

You can also access individual items in this collection by index.

    >>> print e_recipes[1].dish.name
    Foies de voilaille en aspic

    >>> e_recipes[1000]
    Traceback (most recent call last):
    ...
    IndexError: list index out of range

When are representations fetched?
=================================

To avoid unnecessary HTTP requests, a representation of a collection
is fetched at the last possible moment. Let's see what that means.

    >>> import httplib2
    >>> httplib2.debuglevel = 1

    >>> service = CookbookWebServiceClient()
    send: ...
    ...

Just accessing a top-level collection doesn't trigger an HTTP request.

    >>> recipes = service.recipes
    >>> dishes = service.dishes
    >>> cookbooks = service.cookbooks

Getting the length of the collection, or any entry from the
collection, triggers an HTTP request.

    >>> len(recipes)
    send: 'GET /1.0/recipes...
    ...

    >>> dish = dishes[1]
    send: 'GET /1.0/dishes...
    ...

Invoking a named operation will also trigger an HTTP request.

    >>> cookbooks.find_recipes(search="foo")
    send: ...
    ...

Scoped collections work the same way: just getting a reference to the
collection doesn't trigger an HTTP request.

    >>> recipes = dish.recipes

But getting any information about the collection triggers an HTTP request.

    >>> len(recipes)
    send: 'GET /1.0/dishes/.../recipes ...
    ...

Cleanup.

    >>> httplib2.debuglevel = None
